namespace :db do
  desc 'Generate all the database objects of the current project'
  task create_objects: :environment do
    creator = RailsDbObjects::DbObjectsCreator.new

    objects_path = Rails.configuration.rails_db_objects[:objects_path]
    objects_ext = Rails.configuration.rails_db_objects[:objects_ext]

    objects_path.each do |path|
      creator.register_files(Dir[File.join(path, objects_ext)].map { |x| File.expand_path(x) })
    end

    creator.create_objects
  end

  desc 'Drop all the database objects of the current project'
  task drop_objects: :environment do
    creator = RailsDbObjects::DbObjectsCreator.new

    objects_path = Rails.configuration.rails_db_objects[:objects_path]
    objects_ext = Rails.configuration.rails_db_objects[:objects_ext]

    objects_path.each do |path|
      creator.register_files(Dir[File.join(path, objects_ext)].map { |x| File.expand_path(x) })
    end

    creator.drop_objects
  end
end

require 'rake/hooks'

before 'db:migrate' do
  Rake::Task['db:drop_objects'].invoke
end
before 'db:rollback' do
  Rake::Task['db:drop_objects'].invoke
end

after 'db:migrate' do
  Rake::Task['db:create_objects'].invoke
end
after 'db:rollback' do
  Rake::Task['db:create_objects'].invoke
end
