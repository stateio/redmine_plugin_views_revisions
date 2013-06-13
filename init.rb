require 'redmine'

unless Redmine::Plugin.registered_plugins.keys.include?(:redmine_plugin_views_revisions)
  Redmine::Plugin.register :redmine_plugin_views_revisions do
    name 'Redmine plugin views revisions plugin'
    author 'Vitaly Klimov'
    author_url 'mailto:vitaly.klimov@snowbirdgames.com'
    description 'This plugin tries to solve problem that is caused by inability to monkey-patch views in the Redmine. For details please see http://www.redmine.org/plugins/redmine_plugin_views_revisions for more details'
    version '0.0.1'
    requires_redmine :version_or_higher => '1.3.0'
  end
end
