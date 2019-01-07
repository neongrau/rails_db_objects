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
          name: object_name,
          type: object_type,
          debug: false,
          directives: [],
          path: file,
          sql_content: sql_content,
          status: :none,
          requires: [],
          silent: false,
          keep: false,
          nodrop: false,
          deleted: false,
          nocreate: false,
          dbschema: Rails.configuration.rails_db_objects[:objects_dbschema],
          dropsql: [],
          createsql: [],
          vanilla: false,
          condition: [],
          dropconditionruby: [],
          createconditionruby: [],
          beforedropruby: [],
          beforedropsql: [],
          afterdropruby: [],
          afterdropsql: [],
          beforecreateruby: [],
          beforecreatesql: [],
          aftercreateruby: [],
          aftercreatesql: []
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
        @objects[object_type].each do |_name, object|
          drop_object(object)
        end
      end
    end

    def create_objects
      reset_objects_status!
      @objects.keys.each do |object_type|
        @objects[object_type].each do |_name, object|
          create_object(object)
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

    # rubocop:disable Metrics/AbcSize
    def prepare_directive(file_obj, directive)
      file_obj[:debug] = /^!debug/.match?(directive) unless file_obj[:debug]
      file_obj[:directives] << directive
      file_obj[:requires] += directive.split(' ')[1..-1] if /^!require /.match?(directive)
      file_obj[:vanilla] = /^!vanilla/.match?(directive) unless file_obj[:vanilla]
      file_obj[:nocreate] = file_obj[:deleted] = /^!deleted/.match?(directive) unless file_obj[:deleted]
      file_obj[:silent] = /^!silent/.match?(directive) unless file_obj[:silent]
      file_obj[:nodrop] = file_obj[:keep] = /^!keep/.match?(directive) unless file_obj[:keep]
      file_obj[:dbschema] = directive.split(' ')[1..-1] if /^!schema/.match?(directive)
      file_obj[:dropconditionruby] << directive.split(' ')[1..-1].join(' ') if /^!dropconditionruby /.match?(directive)
      file_obj[:createconditionruby] << directive.split(' ')[1..-1].join(' ') if /^!createconditionruby /.match?(directive)
      file_obj[:condition] << directive.split(' ')[1..-1].join(' ') if /^!condition /.match?(directive)
      file_obj[:beforedropsql] << directive.split(' ')[1..-1].join(' ') if /^!beforedropsql /.match?(directive)
      file_obj[:dropsql] << directive.split(' ')[1..-1].join(' ') if /^!dropsql /.match?(directive)
      file_obj[:afterdropsql] << directive.split(' ')[1..-1].join(' ') if /^!afterdropsql /.match?(directive)
      file_obj[:beforecreatesql] << directive.split(' ')[1..-1].join(' ') if /^!beforecreatesql /.match?(directive)
      file_obj[:createsql] << directive.split(' ')[1..-1].join(' ') if /^!createsql /.match?(directive)
      file_obj[:aftercreatesql] << directive.split(' ')[1..-1].join(' ') if /^!aftercreatesql /.match?(directive)
    end
    # rubocop:enable Metrics/AbcSize

    def reset_objects_status!
      @objects.keys.each do |object_type|
        @objects[object_type].each do |_name, object|
          object[:status] = :none
        end
      end
    end

    def conditional_ruby(condition, object)
      interpolated_command = object.instance_eval('"' + condition.gsub(/\"/, '\"') + '"')
      condition = object.instance_eval(interpolated_command)
      if object[:debug]
        puts '=' * 80
        puts "interpolated_command: #{interpolated_command}"
        puts '=' * 80
        puts "condition: #{condition.inspect}"
        puts '=' * 80
      end
      condition ? true : false
    end

    def interpolate_sql(sql, object)
      object.instance_eval('"' + sql.gsub(/\"/, '\"') + '"')
    end

    # rubocop:disable Metrics/AbcSize
    def drop_object(object)
      return if object[:nodrop]

      return if object[:status] == :loaded

      object_type = object[:type]
      name = object[:name]
      @dbschema = (object[:dbschema] || []).clone

      raise "Error: Circular file reference! (#{object_type} #{name})" if object[:status] == :inprogress

      full_name = full(name)

      if object[:dropconditionruby].compact.any?
        condition = conditional_ruby(object[:dropconditionruby].join("\n"), object)
        if condition
          puts "RUBY CONDITION MET FOR #{object_type} #{full_name} #{condition}"
        else
          puts "RUBY CONDITION NOT MET FOR #{object_type} #{full_name} #{condition}"
          return
        end
      elsif object[:condition].compact.any?
        condition = !ActiveRecord::Base.connection.select_rows(object[:condition].join("\n")).empty?
        if condition
          puts "SQL CONDITION MET FOR #{object_type} #{full_name}"
        else
          puts "SQL CONDITION NOT MET FOR #{object_type} #{full_name}"
          return
        end
      end

      if object[:debug]
        puts '=' * 80
        puts "DROP OBJECT #{name} / #{object[:path]}"
        puts '=' * 80
        puts object.to_json
        puts '=' * 80
      end

      object[:requires].each do |requirement|
        requires = requirement.split('/', 2)
        required_object = requires.last
        required_type = requires.first.upcase if requires.length == 2
        required_type ||= object_type
        drop_object @objects[required_type.upcase][required_object]
      end

      sql = if object[:dropsql].compact.empty? && !object[:vanilla]
              "DROP #{object_type} #{full_name};"
            else
              interpolate_sql(object[:dropsql].compact.join(";\n"), object)
            end

      begin
        conditional_ruby(object[:beforedropruby].join("\n"), object) unless object[:beforedropruby].empty?
        ActiveRecord::Base.connection.execute(object[:beforedropsql].join("\n")) unless object[:beforedropsql].empty?
        ActiveRecord::Base.connection.execute(sql)
        ActiveRecord::Base.connection.execute(object[:afterdropsql].join("\n")) unless object[:afterdropsql].empty?
        puts "DROP #{object_type} #{full_name}... OK"
        conditional_ruby(object[:afterdropruby].join("\n"), object) unless object[:afterdropruby].empty?
      rescue StandardError => e
        unless object[:debug]
          puts '#' * 80
          puts e.message.to_s
          # puts "#"*80
          # puts "#{e.backtrace}"
          puts '#' * 80
          puts "WARNING: #{sql}... ERROR"
          puts '#' * 80
        end
      end

      object[:status] = :loaded
    end

    def create_object(object)
      return if object[:nocreate]

      return if object[:status] == :loaded

      object_type = object[:type]
      name = object[:name]

      raise "Error: Circular file reference! (#{object_type} #{name})" if object[:status] == :inprogress

      object[:status] = :inprogress
      @dbschema = (object[:dbschema] || []).clone

      full_name = full(name)

      if object[:createconditionruby].compact.any?
        condition = conditional_ruby(object[:createconditionruby].join("\n"), object)
        if condition
          puts "RUBY CONDITION MET FOR #{object_type} #{full_name} / #{condition}"
        else
          puts "RUBY CONDITION NOT MET FOR #{object_type} #{full_name}"
          return
        end
      elsif object[:condition].compact.any?
        condition = ActiveRecord::Base.connection.select_rows(object[:condition].join("\n")).empty?
        if condition
          puts "CONDITION MET FOR #{object_type} #{full_name}"
        else
          puts "CONDITION NOT MET FOR #{object_type} #{full_name}"
          return
        end
      end

      if object[:debug]
        puts '=' * 80
        puts "CREATE OBJECT #{name} / #{object[:path]}"
        puts '=' * 80
        puts object.to_json
        puts '=' * 80
      end
      # skip empty sql content
      if object[:sql_content].strip.blank?
        puts "#{object_type} #{name} EMPTY... SKIPPING"
        return
      end

      create_dependencies(object, object_type)

      sql = if object[:vanilla]
              interpolate_sql(object[:sql_content], object)
            elsif object[:createsql].compact.empty?
              "CREATE #{object_type} #{full_name}\n#{object[:sql_content]}"
            else
              interpolate_sql(object[:createsql].compact.join(";\n"), object)
            end

      begin
        conditional_ruby(object[:beforecreateruby].join("\n"), object) unless object[:beforecreateruby].empty?
        ActiveRecord::Base.connection.execute(object[:beforecreatesql].join("\n")) unless object[:beforecreatesql].empty?
        ActiveRecord::Base.connection.execute(sql.to_s)
        ActiveRecord::Base.connection.execute(object[:aftercreatesql].join("\n")) unless object[:aftercreatesql].empty?
        conditional_ruby(object[:aftercreateruby].join("\n"), object) unless object[:aftercreateruby].empty?
        puts "CREATE #{object_type} #{full_name}... OK"
      rescue StandardError => e
        unless object[:silent]
          puts '#' * 80
          puts e.message.to_s
          # puts '#' * 80
          # puts "#{e.backtrace}"
          puts '#' * 80
          puts "WARNING: CREATE #{object_type} #{full_name}... ERROR"
          puts '#' * 80
        end
      end

      object[:status] = :loaded
    end
    # rubocop:enable Metrics/AbcSize

    def create_dependencies(object, object_type)
      object[:requires].each do |requirement|
        requires = requirement.split('/', 2)
        required_object = requires.last
        required_type = requires.first.upcase if requires.length == 2
        required_type ||= object_type
        create_object(@objects[required_type.upcase][required_object])
      end
    end
  end
end
