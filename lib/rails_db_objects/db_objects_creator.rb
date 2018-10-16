module RailsDbObjects
  class DbObjectsCreator
    attr_reader :objects

    def initialize
      @objects = {}
    end

    def register_files(files)
      files.each do |file|
        object_name = File.basename(file, File.extname(file))
        object_type = File.dirname(file.to_s).to_s.split('/').last.upcase

        @objects[object_type] ||= {}

        content = File.read(file)
        content_lines = content.split("\n")

        # Reject the commented lines from the file
        sql_content = content_lines.reject { |x| x.strip =~ /^--/ || x.strip =~ /^#/ }.join("\n")

        file_obj = {
          path: file,
          sql_content: sql_content,
          status: :none,
          requires: [],
          silent: false,
          keep: false,
          deleted: false,
          dbschema: Rails.configuration.rails_db_objects[:objects_dbschema],
          dropsql: [],
          createsql: [],
          vanilla: false,
          condition: []
        }

        # Detect directives in commentary
        directives = extract_from_comments(content_lines)

        # puts "directives: #{directives.inspect}"
        directives.each { |directive| prepare_directive(file_obj, directive) }

        @objects[object_type][object_name] = file_obj
      end
    end

    def drop_objects
      reset_objects_status!
      @objects.keys.each do |object_type|
        @objects[object_type].each do |name, object|
          drop_object(object_type, name, object) unless object[:skip_pre]
        end
      end
    end

    def create_objects
      reset_objects_status!
      @objects.keys.each do |object_type|
        @objects[object_type].each do |name, object|
          create_object(object_type, name, object) unless object[:skip_post]
        end
      end
    end

    private

    def full(name)
      prefix = @dbschema.blank? ? '' : "#{@dbschema}."
      "#{prefix}#{wrap_name(name)}"
    end

    def wrap_name(name)
      adapter_name = ActiveRecord::Base.connection.adapter_name

      case adapter_name
      when 'PostgreSQL'
        "\"#{name}\""
      when 'MySQL'
        "`#{name}`"
      when 'SQLServer'
        "[#{name}]"
      end
    end

    def extract_from_comments(content_lines)
      dir_lines = content_lines.select { |x| x.strip =~ /^--/ || x.strip =~ /^#/ }.map(&:strip)
      dir_lines.map { |x| /^--/.match?(x) ? x[2..-1] : x[1..-1] }.select { |x| x =~ /^!/ }
    end

    def prepare_directive(file_obj, directive)
      file_obj[:requires] += directive.split(' ')[1..-1] if /^!require /.match?(directive)
      file_obj[:vanilla] = /^!vanilla/.match?(directive)
      file_obj[:skip_post] = /^!deleted/.match?(directive)
      file_obj[:silent] = /^!silent/.match?(directive)
      file_obj[:skip_pre] = /^!keep/.match?(directive)
      file_obj[:dbschema] = directive.split(' ')[1..-1] if /^!schema/.match?(directive)
      file_obj[:condition] << directive.split(' ')[1..-1].join(' ') if /^!condition /.match?(directive)
      file_obj[:dropsql] << directive.split(' ')[1..-1].join(' ') if /^!dropsql /.match?(directive)
      file_obj[:createsql] << directive.split(' ')[1..-1].join(' ') if /^!createsql /.match?(directive)
    end

    def reset_objects_status!
      @objects.keys.each do |object_type|
        @objects[object_type].each do |_name, object|
          object[:status] = :none
        end
      end
    end

    def drop_object(object_type, name, object)
      return if object[:status] == :loaded

      if object[:status] == :inprogress
        raise "Error: Circular file reference! (#{object_type} #{name})"
      end

      object[:requires].each do |requirement|
        requires = requirement.split('/', 2)
        required_object = requires.last
        required_type = requires.first.upcase if requires.length == 2
        required_type ||= object_type
        drop_object required_type, required_object, @objects[required_type.upcase][required_object]
      end

      @dbschema = (object[:dbschema] || []).clone
      full_name = full(name)

      sql = if object[:vanilla]
              object[:sql_content]
            elsif object[:dropsql].compact.empty?
              "DROP #{object_type} #{full_name};"
            else
              object[:dropsql].compact.join(";\n")
            end

      begin
        unless object[:condition].compact.empty?
          condition = !ActiveRecord::Base.connection.select_rows(object[:condition].join("\n")).empty?
          if condition
            puts "CONDITION MET FOR #{object_type} #{full_name}"
          else
            puts "CONDITION NOT MET FOR #{object_type} #{full_name}"
            return
          end
        end
        ActiveRecord::Base.connection.execute(sql)
        puts "#{sql}... OK"
      rescue StandardError => e
        unless object[:silent]
          puts '#' * 80
          puts e.message.to_s
          # puts "#"*80
          # puts "#{e.backtrace}"
          puts '#' * 80
          puts "WARNING: #{sql}... ERROR"
          puts '#' * 80
          # else
          #   puts "WARNING: #{sql}... SILENT"
        end
      end

      object[:status] = :loaded
    end

    def create_object(object_type, name, object)
      # skip empty sql content
      if object[:sql_content].strip.blank?
        puts "#{object_type} #{name} EMPTY... SKIPPING"
        return
      end

      # object already loaded.
      return if object[:status] == :loaded

      raise "Error: Circular file reference! (#{object_type} #{name})" if object[:status] == :inprogress

      object[:status] = :inprogress

      create_dependencies(object, object_type)

      @dbschema = (object[:dbschema] || []).clone
      full_name = full(name)

      sql = if object[:vanilla]
              object[:sql_content]
            elsif object[:createsql].compact.empty?
              "CREATE #{object_type} #{full_name}\n#{object[:sql_content]}"
            else
              object[:createsql].compact.join("\n")
            end

      begin
        unless object[:condition].compact.empty?
          condition = ActiveRecord::Base.connection.select_rows(object[:condition].join("\n")).empty?
          if condition
            puts "CONDITION MET FOR #{object_type} #{full_name}"
          else
            puts "CONDITION NOT MET FOR #{object_type} #{full_name}"
            return
          end
        end
        ActiveRecord::Base.connection.execute(sql.to_s)
        puts "CREATE #{object_type} #{full_name}... OK"
      rescue StandardError => e
        unless object[:silent]
          puts '#' * 80
          puts e.message.to_s
          # puts "#"*80
          # puts "#{e.backtrace}"
          puts '#' * 80
          puts "WARNING: CREATE #{object_type} #{full_name}... ERROR"
          puts '#' * 80
          # else
          #   puts "WARNING: CREATE #{object_type} #{full_name}... SILENT"
        end
      end

      object[:status] = :loaded
    end

    def create_dependencies(object, object_type)
      object[:requires].each do |requirement|
        requires = requirement.split('/', 2)
        required_object = requires.last
        required_type = requires.first.upcase if requires.length == 2
        required_type ||= object_type
        create_object required_type, required_object, @objects[required_type.upcase][required_object]
      end
    end
  end
end
