class RailsDbObjects::DbObjectsCreator
  attr_reader :objects

  def initialize
    @objects = {}
  end

  def register_files files
    files.each do |file|
      object_name = File.basename(file, File.extname(file))
      object_type = File.dirname(file.to_s).to_s.split('/').last.upcase

      @objects[object_type] ||= {}

      content = File.read(file)
      content_lines = content.split("\n")

      # Reject the commented lines from the file
      sql_content = content_lines.reject{ |x| x.strip =~ /^--/ || x.strip =~ /^#/ }.join("\n")

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
      directives = content_lines.select{ |x| x.strip =~ /^--/ || x.strip =~ /^#/ }.map(&:strip).map{ |x| 
        x =~ /^--/ ? x[2..-1] : x[1..-1]
      }.select{|x| x =~ /^!/ }

      #puts "directives: #{directives.inspect}"
      directives.each do |directive|
        if directive =~ /^!require /
          file_obj[:requires] += directive.split(" ")[1..-1]
        end
        if directive =~ /^!vanilla/
          file_obj[:vanilla] = true
        end
        if directive =~ /^!deleted/
          file_obj[:skip_post] = true
        end
        if directive =~ /^!silent/
          file_obj[:silent] = true
        end
        if directive =~ /^!keep/
          file_obj[:skip_pre] = true
        end
        if directive =~ /^!schema/
          file_obj[:dbschema] = directive.split(" ")[1..-1]
        end
        if directive =~ /^!condition /
          file_obj[:condition] << directive.split(" ")[1..-1].join(" ")
        end
        if directive =~ /^!dropsql /
          file_obj[:dropsql] << directive.split(" ")[1..-1].join(" ")
        end
        if directive =~ /^!createsql /
          file_obj[:createsql] << directive.split(" ")[1..-1].join(" ")
        end
      end

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
  def reset_objects_status!
    @objects.keys.each do |object_type|
      @objects[object_type].each do |name, object|
        object[:status] = :none
      end
    end
  end


  def drop_object object_type, name, object
    return if object[:status] == :loaded

    if object[:status] == :inprogress
      raise "Error: Circular file reference! (#{object_type} #{name})"
    end

    object[:requires].each do |requirement|
      requires = requirement.split('/', 2)
      required_object = requires.last
      required_type = requires.first.upcase if requires.length==2
      required_type ||= object_type
      drop_object required_type, required_object, @objects[required_type.upcase][required_object]
    end

    dbschema = (object[:dbschema] || []).clone
    full_name = [dbschema, "[#{name}]"].flatten.reject(&:blank?).compact.join('.')

    if object[:vanilla]
      sql = object[:sql_content]
    else
      unless object[:dropsql].compact.empty?
        sql = object[:dropsql].compact.join("\n")
      else
        sql = "DROP #{object_type} #{full_name}"
      end
    end

    begin
      unless object[:condition].compact.empty?
        condition = !ActiveRecord::Base.connection.select_rows(object[:condition].join("\n")).empty?
        unless condition
          puts "CONDITION NOT MET FOR #{object_type} #{full_name}" 
          return
        else
          puts "CONDITION MET FOR #{object_type} #{full_name}" 
        end
      end
      ActiveRecord::Base.connection.execute(sql)
      puts "#{sql}... OK"
    rescue => e
      unless object[:silent]
        puts "#"*80
        puts "#{e.message}"
        #puts "#"*80
        #puts "#{e.backtrace}"
        puts "#"*80
        puts "WARNING: #{sql}... ERROR"
        puts "#"*80
      # else
      #   puts "WARNING: #{sql}... SILENT"
      end
    end

    object[:status] = :loaded
  end

  def create_object object_type, name, object
    # skip empty sql content
    if object[:sql_content].strip.blank?
      puts "#{object_type} #{name} EMPTY... SKIPPING"
      return
    end

    # object already loaded.
    return if object[:status] == :loaded

    if object[:status] == :inprogress
      raise "Error: Circular file reference! (#{object_type} #{name})"
    end

    object[:status] = :inprogress

    object[:requires].each do |requirement|
      requires = requirement.split('/', 2)
      required_object = requires.last
      required_type = requires.first.upcase if requires.length==2
      required_type ||= object_type
      create_object required_type, required_object, @objects[required_type.upcase][required_object]
    end

    dbschema = (object[:dbschema] || []).clone
    full_name = [dbschema, "[#{name}]"].flatten.reject(&:blank?).compact.join('.')

    if object[:vanilla]
      sql = object[:sql_content]
    else
      unless object[:createsql].compact.empty?
        sql = object[:createsql].compact.join("\n")
      else
        sql = "CREATE #{object_type} #{full_name}\n#{object[:sql_content]}"
      end
    end

    begin
      unless object[:condition].compact.empty?
        condition = ActiveRecord::Base.connection.select_rows(object[:condition].join("\n")).empty?
        unless condition
          puts "CONDITION NOT MET FOR #{object_type} #{full_name}" 
          return
        else
          puts "CONDITION MET FOR #{object_type} #{full_name}" 
        end
      end
      ActiveRecord::Base.connection.execute("#{sql}")
      puts "CREATE #{object_type} #{full_name}... OK"
    rescue => e
      unless object[:silent]
        puts "#"*80
        puts "#{e.message}"
        #puts "#"*80
        #puts "#{e.backtrace}"
        puts "#"*80
        puts "WARNING: CREATE #{object_type} #{full_name}... ERROR"
        puts "#"*80
      # else
      #   puts "WARNING: CREATE #{object_type} #{full_name}... SILENT"
      end
    end

    object[:status] = :loaded
  end

end
