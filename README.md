# RailsDbObjects

A tool to manage database objects like views, functions, triggers, stored procedures or assemblies.

Inspired by the rails_db_views gem (which you can find at https://github.com/anykeyh/rails_db_views) and re-using a lot of the code from there.
This gem does practically the same for (views and function) but also supports triggers and stored procedures and even assemblies (for MS SQL) or maybe even indexes or tables (not that you should since these should go into proper migrations).
There is not much difference in managing these objects since all are created and dropped by the same "CREATE" and "DROP" syntax. Also the "directive" like "require" now supports (optional) definition of other objects so a "view" can require a "function" or vice versa in whatever combination you want.

# How does it work?

First add rails_db_objects to your Gemfile:

```Gemfile
gem 'rails_db_objects'
```

Under db/objects you can create directories for whatever object type you want to manage.
It only depends on what your DB engine supports. The name of each directory will be used as the type of object and will directly be used in the generated SQL. Inside the directories .sql files will be placed where the file name is being used as the objects name.

    Examples:
    db/objects/view/exampleView.sql
    db/objects/trigger/someTrigger.sql
    db/objects/function/myFunction.sql

The content of the .sql files will be everything except the "CREATE..." or "DROP..." part of the SQL. So a typical view for example will start with "AS SELECT...".

# Special directives

Written as SQL comments with two dashes "--" the gem supports a few directives that can optionally have parameters.
Supported directives are

All SQL or Ruby-Condition comments allow multiple lines. And also interpolated ruby with `#{Some.ruby(code)}`. If required some information about the current element is accesible via `#{self}`. So for example if you have a more complicated SQL statement you wish to run before the create you can write those this way:
```sql
--!beforecreatesql SELECT *...
--!beforecreatesql FROM...
--!beforecreatesql WHERE...
```

 - --!debug
    - Prints some useful information about the current object on the command line during processing when `rails db:migrate` triggers drop or create of this element.
 - --!require view/exampleView
    - The require is used for ordering and to ensure a specific object will be made available before this .sql file is processed. By defining the type before the required item's name you can freely require whatever item from another type you desire.
 - --!deleted or --!nocreate
    - The item is meant to be deleted and will be skipped during CREATE. Making sure it will not be re-created again.
 - --!keep or --!nodrop
    - The item will not be deleted during processing the DROP.
 - --!silent
    - If either DROP or CREATE fails, only a line with a warning will be shown. Otherwise the SQL error message will be displayed
 - --!schema guest
    - The specified schema (e.g. guest) will be used for this object instead of the default (dbo). The parameter can be omitted so a simple "--!schema" line will cause this object to be processed without a schema (overriding the default).
 - --!beforedropsql ...your sql here..
    - The gem will just execute the SQL before the actual drop happens.
 - --!dropsql ...your sql here..
    - Instead of buidling the SQL from object name and file name and file content during DROP, the gem will just execute the SQL of that line.
 - --!afterdropsql ...your sql here..
    - The gem will just execute the SQL after the actual drop happened.
 - --!beforecreatesql ...your sql here..
    - The gem will just execute the SQL before the actual create happens.
 - --!createsql ...your sql here...
    - Instead of buidling the SQL from object name and file name and file content during CREATE, the gem will just execute the SQL of that line.
 - --!aftercreatesql ...your sql here..
    - The gem will just execute the SQL after the actual create happened.
 - --!condition ...your sql here...
    - Executes the SQL and will skip the DROP if that sql returns an empty result (as in the object does not exist).
      The CREATE will be skipped if that sql returns one ore more results as the object already/still exists.
 - --!dropconditionruby Some.ruby(code) ? true : false
    - Will execute the code via eval and if the result is Boolean True the drop will be executed. Overrides the generic SQL based `--!condition`
 - --!createconditionruby Some.ruby(code) ? true : false
    - Will execute the code via eval and if the result is Boolean True the create will be executed. Overrides the generic SQL based `--!condition`
 - --!vanilla
    - Will execute just the contents of the .sql file. No DROP or CREATE or name will be appended. Also the folder name the .sql file resides in will not affect the result. Will be executed during DROP and CREATE unless combined with other directives.

## Configurate paths & extensions

You can add/remove the path in the initializers of Rails:

```ruby
Rails.application.config.rails_db_objects[:objects_path] += %w( /db/objects )
Rails.application.config.rails_db_objects[:objects_ext] = '*.sql'
Rails.application.config.rails_db_objects[:objects_dbschema] = 'base' # can be set to nil if none should be used
```

# Licensing

Based on rails_db_views https://github.com/anykeyh/rails_db_views

MIT. Use it, fork it, have fun!
