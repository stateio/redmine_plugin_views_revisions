
desc <<-END_DESC
Updates given plugins files to new redmine version/revision

Available options:
  * log       => name of the log file, stdout otherwise
  * plugins   => comma separated list of plugins to process, otherwise all plugins are processed

Example:
  rake redmine:plugins:process_version_change log="migration.log" plugins="redmine_boards_watchers,redmine_default_columns" RAILS_ENV="production"
END_DESC

namespace :redmine do
  namespace :plugins do
    task :process_version_change => :environment do

      require 'plugin_process_version_change'

      plugins=(ENV['plugins'] || '').split(',').each(&:strip!)
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
  end
end
