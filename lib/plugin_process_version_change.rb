require 'redmine'
require "yaml"

# file naming rules
#   revision(=|!)-version_high.version_low.version_tiny(=|!)-original_filename
#
# Use revision 0000 for default files
#
# *Meaning of postfixes*
# = - means that file is valid for exact revision/version *only*
# ! - means that file should not be copied if redmine' version/revision is greater than this
# *Files validity check*
# filename has revision
#   if revision of redmine is unknown then revision is taken from _redmine_revisions.yml_ file
#   file is valid if redmine revision is higher or equal
#   if equal sign presents file is valid *only* if the revision matches redmine revision
# filename has only version
#   file is valid if redmine version is higher or equal
#   if equal sign presents file is valid *only* if the version matches redmine version
# filename has both version and revision
#   if revision of redmine is known then rules for revision apply
#   if revision of redmine is unknown then rules for version apply
#
# *Selection rules*
# if there are file that has equal sign it is chosen
# otherwise file with highest revision/version is chosen

module PluginProcessVersionChange

  VIEWS_REVISIONS_FOLDER = 'rev'

  def self.process_rake_task(default_plugins=nil)
    plugins=(ENV['plugins'] || '').split(',').each(&:strip!)
    plugins += default_plugins if plugins.size == 0 && default_plugins
    log=ENV['log'] ? StringIO.new('') : nil
    vrr=PluginProcessVersionChange::PluginsWithRevision.new
    vrr.execute(plugins.size > 0 ? plugins : nil,log)
    if log
      log_file=File.new(ENV['log'], "w")
      log_file.binmode
      log_file.write(log.string)
      log_file.close
    end
  end

  class PluginsWithRevision
    def initialize
      @redmine_revision=0
      @redmine_version=nil
      @log_file=nil
      @revisions_map=YAML.load_file(File.join(File.dirname(__FILE__), '../config/redmine_revisions.yml'))
    end

    def execute(list_of_plugins=nil,log=nil)
      self.log_file=log if log
      unless list_of_plugins.is_a?(Array)
        plugins=[]
        Redmine::Plugin.registered_plugins.each_key do |name|
          plugins << name.to_s
        end
      else
        plugins=list_of_plugins
      end
      log_file.write("Redmine version: #{redmine_version}\n")
      log_file.write("Redmine revision: #{redmine_revision ? redmine_revision : 'unknown'}\n")
      log_file.write('-'*10 + " Updating revisions.... "+ '-'*10+"\n")
      plugins_folder=File.join(File.dirname(__FILE__),'../..')
      plugins.each do |name|
        log_file.write('-'*8 + " processing plugin #{name} \n")
        process_folder_tree(File.join(plugins_folder,name,VIEWS_REVISIONS_FOLDER),File.join(plugins_folder,name))
      end
      log_file.write("Done\n")
      self.log_file=nil
    end

    def log_file=(log)
      @log_file=log
    end

    def log_file
      @log_file=STDOUT unless @log_file
      @log_file
    end

    def redmine_revision
      if @redmine_revision == 0
        @redmine_revision=nil
        # check if we have special .revision file in rails_root to override default
        rev_path="#{Rails.root}/.revision"
        if File.readable?(rev_path)
          f=File.open(rev_path,'r')
          rev_entries=f.read.split(/(\r\n|\r|\n)/)
          f.close
          if rev_entries.size > 0 && (rev_entries.first =~ /^\.ignore$/) == nil
            @redmine_revision=$1.to_i if rev_entries.first =~ /^(\d+)$/
          end
        else
          @redmine_revision=Redmine::VERSION::REVISION
        end
      end
      @redmine_revision
    end

    def redmine_version
      unless @redmine_version
        va=[Redmine::VERSION::MAJOR,Redmine::VERSION::MINOR,Redmine::VERSION::TINY]
        # special file for test cases
        rev_path="#{Rails.root}/.version"
        if File.readable?(rev_path)
          f=File.open(rev_path,'r')
          rev_entries=f.read.split(/(\r\n|\r|\n)/)
          f.close
          va=[$1,$2,$3] if rev_entries.size > 0 && rev_entries.first =~ /^(\d+)\.(\d+)\.(\d+)$/
        end
        @redmine_version=va.compact.join('.')
      end
      @redmine_version
    end

  private
    def process_folder_tree(base_dir,dst_dir)
      files_hash={}
      process_entries_in_folder(base_dir,'',files_hash)

      files_hash.each_pair do |fnm,revs|
        revision=get_matching_revision(revs,redmine_revision,redmine_version)
        FileUtils.rm(File.join(dst_dir,fnm),:force => true)
        if revision
          FileUtils.mkdir_p(File.join(dst_dir,revision[:base_dir]))
          FileUtils.copy_file(File.join(base_dir,revision[:base_dir],revision[:org_name]),File.join(dst_dir,fnm),true)
          log_file.write("    Using")
          log_file.write(" version #{revision[:ver]}") if revision[:ver].size > 0
          log_file.write(" revision #{revision[:rev]}") if revision[:rev].size > 0
          log_file.write(" for file #{fnm}\n")
        else
          log_file.write("    Removing obsolete file #{fnm}\n")
        end
      end
    end

    # returns revision (int) based on passed redmine version string
    def get_revision_from_version(version_string=nil)
      @revisions_map[version_string || redmine_version]
    end

    def process_entries_in_folder(root_dir,base_dir,files_hash)
      entries=Dir[File.join(root_dir,base_dir,'*')]
      entries.each do |entry|
        name=File.basename(entry)
        if File.directory?(entry)
          process_entries_in_folder(root_dir,File.join(base_dir,name),files_hash)
        else
          if name =~ /^((\d+)([=!]|)\-|)((\d+\.\d+\.\d+)([=!]|)\-|)(.*)/
            rev=$2 || ''
            rev_strict=$3 || ''
            ver=$5 || ''
            ver_strict=$6 || ''
            dir=$7 || ''
            if dir.size > 0 && (rev.size > 0 || ver.size >0)
              ver='' if rev.size > 0 && redmine_revision
              rev='' if ver.size > 0 && redmine_revision == nil
              dir_full=File.join(base_dir,dir)
              files_hash[dir_full]=[] if files_hash[dir_full].blank?
              files_hash[dir_full] << {:org_name => name,:rev => rev,:base_dir => base_dir,
                                       :ver => ver, :rev_strict => rev_strict, :ver_strict => ver_strict}
            end
          end
        end
      end
    end

    def get_matching_revision(revs,rev,ver)
      return nil unless revs.size > 0

      redmine_elem={:rev => rev.nil? ? '' : rev.to_s, :ver => ver, :ver_strict => '=', :rev_strict => '='}
      exact_version=nil
      qr=revs.select do |elem|
        unless exact_version
          r=false
          c=compare_two_file_entries(elem,redmine_elem)
          if c <= 0
            if ( elem[:ver_strict] == '=' && ( elem[:rev].size == 0 || redmine_revision == nil)) || elem[:rev_strict] == '='
              if c == 0
                exact_version=elem
                r=true
              end
            else
              r=true
            end
          end
          r
        else
          false
        end
      end

      return nil unless qr.size > 0
      return exact_version unless exact_version.nil?

      qr=qr.sort do |a,b|
        compare_two_file_entries(a,b)
      end

      exact_version=qr.last

      if exact_version[:rev_strict] == '!'
        unless rev.nil?
          return nil if exact_version[:rev].to_i < rev.to_i
        else
          v=(exact_version[:ver].size == 0 ? get_version_by_revision(exact_version[:rev].to_i) : exact_version[:ver])
          return nil if compare_two_versions(v,redmine_version) < 0
        end
      end

      if exact_version[:ver_strict] == '!' && exact_version[:rev].size == 0
        return nil if compare_two_versions(exact_version[:ver],redmine_version) < 0
      end

      return exact_version
    end

    def compare_two_file_entries(elem1,elem2)
      return elem1[:rev].to_i <=> elem2[:rev].to_i if elem1[:rev].size > 0 && elem2[:rev].size > 0

      ver1=(elem1[:ver].size > 0 ? elem1[:ver] : get_version_by_revision(elem1[:rev].to_i))
      ver2=(elem2[:ver].size > 0 ? elem2[:ver] : get_version_by_revision(elem2[:rev].to_i))
      rev1=(elem1[:rev].size > 0 ? elem1[:rev] : @revisions_map[ver1])
      rev2=(elem2[:rev].size > 0 ? elem2[:rev] : @revisions_map[ver2])

      c=compare_two_versions(ver1,ver2)
      if c==0
        return -1 unless rev1
        return 1 unless rev2
        return rev1.to_i <=> rev2.to_i
      end
      return c
    end

    def compare_two_versions(ver1,ver2)
      va1=ver1.split('.').collect(&:to_i)
      va2=ver2.split('.').collect(&:to_i)

      va1 <=> va2
    end

    def get_version_by_revision(rev)
      rev_array=@revisions_map.to_a.select { |re| true if re[1] >= rev }.sort { |a,b| a[1] <=> b[1] }

      return rev_array.size > 0 ? rev_array.last[0] : '0.0.0'
    end
  end

end
