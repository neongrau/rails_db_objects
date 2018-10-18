class Railtie < Rails::Railtie
  railtie_name :rails_db_objects

  config.rails_db_objects = ActiveSupport::OrderedHash.new

  initializer 'rails_db_objects.initialize' do |app|
    app.config.rails_db_objects[:objects_path] = %w[db/objects/**/]
    app.config.rails_db_objects[:objects_ext] = '*.sql'
    app.config.rails_db_objects[:objects_dbschema] = ['dbo']
  end

  rake_tasks do
    load 'tasks/rails_db_objects_tasks.rake'
  end
end
