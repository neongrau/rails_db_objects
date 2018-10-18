$LOAD_PATH.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'rails_db_objects/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'rails_db_objects'
  s.version     = RailsDbObjects::VERSION
  s.authors     = ['']
  s.email       = ['']
  s.homepage    = 'https://github.com/neongrau/rails_db_objects'
  s.summary     = 'Drops and Creates database objects via rake/hook before and after any rake db:migrate call.'
  s.description = 'A tool to manage database objects like views, functions, triggers, stored procedures or assemblies.
                   Inspired by the rails_db_views gem (which you can find at https://github.com/anykeyh/rails_db_views)
                   and re-using a lot of the code from there.'
  s.license     = 'MIT'

  s.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.rdoc']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'rake-hooks'

  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rubocop-rspec'
end
