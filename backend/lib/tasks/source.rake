# Provisioning helpers for the source database. ActiveRecord migrations create the SQL tables
# (bin/rails db:migrate); MongoDB collections and validators come from mongo:setup.

namespace :mongo do
  desc "Create lists/todos collections with the $jsonSchema validators the write API's default Mongo mapper requires"
  task setup: :environment do
    abort "DATABASE_TYPE is not mongodb" unless SourceDatabase.mongodb?

    validators = {
      "lists" => {
        bsonType: "object",
        required: %w[owner_id],
        properties: {
          _id: { bsonType: "string" },
          owner_id: { bsonType: "string" },
          name: { bsonType: %w[string null] },
          created_at: { bsonType: %w[date null] }
        }
      },
      "todos" => {
        bsonType: "object",
        required: %w[list_id title],
        properties: {
          _id: { bsonType: "string" },
          list_id: { bsonType: "string" },
          title: { bsonType: "string" }, # null title → DOCUMENT_VALIDATION_FAILURE
          completed: { bsonType: %w[bool null] },
          # "number" accepts int and double: the driver stores whole numbers as int32.
          position: { bsonType: %w[number null] },
          created_at: { bsonType: %w[date null] },
          updated_at: { bsonType: %w[date null] }
        }
      }
    }

    db = Mongoid.default_client.database
    existing = db.collection_names
    validators.each do |name, schema|
      if existing.include?(name)
        db.command(collMod: name, validator: { "$jsonSchema" => schema }, validationLevel: "strict", validationAction: "error")
        puts "updated validator on #{name}"
      else
        db.command(create: name, validator: { "$jsonSchema" => schema }, validationLevel: "strict", validationAction: "error")
        puts "created #{name} with validator"
      end
    end
    db[:lists].indexes.create_one({ owner_id: 1 })
    db[:todos].indexes.create_one({ list_id: 1 })
    puts "Restart the write API so it rediscovers the validators."
  end

  desc "Drop the $jsonSchema validators (exercises the write API's SCHEMA_MISMATCH path after a restart)"
  task drop_validators: :environment do
    db = Mongoid.default_client.database
    %w[lists todos].each { |name| db.command(collMod: name, validator: {}, validationLevel: "off") }
    puts "Validators removed. Restart the write API."
  end
end

namespace :postgres do
  desc "Create the logical replication publication PowerSync replicates from"
  task publication: :environment do
    conn = ActiveRecord::Base.connection
    abort "DATABASE_TYPE is not postgres" unless conn.adapter_name.match?(/postg/i)
    exists = conn.select_value("SELECT 1 FROM pg_publication WHERE pubname = 'powersync'")
    if exists
      conn.execute("ALTER PUBLICATION powersync SET TABLE lists, todos")
    else
      conn.execute("CREATE PUBLICATION powersync FOR TABLE lists, todos")
    end
    puts "publication powersync covers lists, todos"
  end
end

namespace :mssql do
  desc "Enable CDC on the database, the lists/todos tables and the _powersync_checkpoints table (needed by PowerSync's SQL Server source)"
  task enable_cdc: :environment do
    conn = ActiveRecord::Base.connection
    abort "DATABASE_TYPE is not mssql" unless conn.adapter_name.match?(/sqlserver/i)
    db_name = conn.current_database
    unless conn.select_value("SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME()") == true
      # RDS forbids sys.sp_cdc_enable_db; it provides this wrapper instead.
      on_rds = conn.select_value("SELECT OBJECT_ID('msdb.dbo.rds_cdc_enable_db')").present?
      conn.execute(on_rds ? "EXEC msdb.dbo.rds_cdc_enable_db #{conn.quote(db_name)}" : "EXEC sys.sp_cdc_enable_db")
    end
    # PowerSync's SQL Server source writes to this table to produce replication checkpoints, and requires
    # CDC on it too. Definition from the PowerSync SQL Server setup docs.
    conn.execute(<<~SQL)
      IF OBJECT_ID(N'dbo._powersync_checkpoints', N'U') IS NULL
      CREATE TABLE dbo._powersync_checkpoints (
        id INT IDENTITY PRIMARY KEY,
        last_updated DATETIME NOT NULL DEFAULT GETUTCDATE()
      )
    SQL
    %w[lists todos _powersync_checkpoints].each do |table|
      tracked = conn.select_value("SELECT is_tracked_by_cdc FROM sys.tables WHERE name = #{conn.quote(table)}")
      next if tracked == true
      conn.execute("EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = #{conn.quote(table)}, @role_name = NULL, @supports_net_changes = 0")
      puts "CDC enabled on #{table}"
    end
  end
end
