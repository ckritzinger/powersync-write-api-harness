# Seed data for manual testing (lib/seed_data.rb). Writes straight to the source database, like
# migrations; PowerSync then replicates the rows to clients. The web app itself stays read-only.
namespace :harness do
  desc "Insert the seed lists/todos (several users, mixed states). Idempotent: existing ids are left as they are"
  task seed: :environment do
    require_relative "../seed_data"
    lists, todos = SeedData.lists, SeedData.todos
    inserted = SourceDatabase.mongodb? ? HarnessSeed.mongo(lists, todos) : HarnessSeed.sql(lists, todos)
    puts "Seeded #{inserted[:lists]}/#{lists.size} lists and #{inserted[:todos]}/#{todos.size} todos " \
         "(others already present) for #{SeedData::OWNERS.join(', ')}."
  end

  desc "DELETE ALL rows from lists and todos (seeded or not), then seed"
  task reset: :environment do
    if SourceDatabase.mongodb?
      db = Mongoid.default_client.database
      puts "Deleted #{db[:todos].delete_many({}).deleted_count} todos, #{db[:lists].delete_many({}).deleted_count} lists"
    else
      conn = ActiveRecord::Base.connection
      conn.transaction do
        todos = conn.delete("DELETE FROM #{conn.quote_table_name('todos')}")
        lists = conn.delete("DELETE FROM #{conn.quote_table_name('lists')}")
        puts "Deleted #{todos} todos, #{lists} lists"
      end
    end
    Rake::Task["harness:seed"].invoke
  end
end

module HarnessSeed
  module_function

  def sql(lists, todos)
    conn = ActiveRecord::Base.connection
    counts = { lists: 0, todos: 0 }
    conn.transaction do
      # Lists first: todos.list_id has a foreign key.
      lists.each { |row| counts[:lists] += 1 if insert_missing(conn, "lists", row) }
      todos.each { |row| counts[:todos] += 1 if insert_missing(conn, "todos", row) }
    end
    counts
  end

  # Plain INSERTs with adapter quoting, so the same code covers Postgres, MySQL and SQL Server.
  def insert_missing(conn, table, row)
    t = conn.quote_table_name(table)
    return false if conn.select_value("SELECT 1 FROM #{t} WHERE id = #{conn.quote(row['id'])}")
    columns = row.keys.map { |c| conn.quote_column_name(c) }.join(", ")
    values = row.values.map { |v| conn.quote(v) }.join(", ")
    conn.execute("INSERT INTO #{t} (#{columns}) VALUES (#{values})")
    true
  end

  # Documents use the UUID as a string _id; field types satisfy the $jsonSchema validators
  # from mongo:setup (dates as BSON dates, completed as bool, position as double).
  def mongo(lists, todos)
    db = Mongoid.default_client.database
    counts = { lists: 0, todos: 0 }
    { lists: lists, todos: todos }.each do |collection, rows|
      rows.each do |row|
        # _id comes from the filter on insert; it may not appear in the update document.
        result = db[collection].update_one({ _id: row["id"] }, { "$setOnInsert" => row.except("id") }, upsert: true)
        counts[collection] += 1 if result.upserted_id
      end
    end
    counts
  end
end

# The token signing keypair (keys/ at the harness root; see app/services/signing_key.rb).
namespace :keys do
  desc "Create the signing key if missing, and print where it is and what to copy where"
  task generate: :environment do
    key, created = SigningKey.load_or_create
    puts(created ? "Generated a new signing key." : "Using the existing signing key.")
    puts "  private key: #{SigningKey.pem_path}   (host: keys/signing-key.pem, gitignored — never share it)"
    puts "  public JWKS: #{SigningKey.jwks_path}   (host: keys/jwks.json — this is the file to copy)"
    puts
    puts "Public JWKS — PowerSync instance client auth (rake connect in powersync/ does this for you):"
    puts JSON.pretty_generate(key.jwks)
    puts
    puts "Write API, backend/powersync-config.json (inline keys, no network fetch):"
    puts JSON.pretty_generate({ "config" => { "client_auth" => { "jwks" => key.jwks } } })
    puts
    puts "Write API, expected issuer and audience (environment variables, e.g. its .env.local):"
    puts "AUTH_ISSUER=#{TokenIssuer.issuer}"
    puts "AUTH_AUDIENCE=#{(TokenIssuer.audience rescue '<set JWT_AUDIENCE or POWERSYNC_URL in backend/.env>')}"
    puts
    puts "Or have the write API fetch the key (this app must be running):"
    puts "AUTH_JWKS_URI_OVERRIDE=http://host.docker.internal:3000/.well-known/jwks.json"
    puts "AUTH_ALLOW_INSECURE_HTTP_HOSTS=host.docker.internal"
  end
end
