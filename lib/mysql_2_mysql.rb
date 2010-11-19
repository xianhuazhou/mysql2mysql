#
# == Description
#
# dump table's structure and data between mysql servers and databases.
#
# == Example
#
#   Please read README.rdoc
#
# == Version
# 
#   v0.0.1
#
# == Author
#
#   xianhua.zhou<xianhua.zhou@gmail.com>
#
require 'sequel'

class Mysql2Mysql 

  VERSION = '0.0.1'

  def self.version
    VERSION
  end

  @@methods = %w(from to tables exclude)

  def initialize(opts = {})
    @@methods.each do |method_name|
      send method_name, opts[method_name.to_sym] or opts[method_name.to_s]
    end
  end

  @@methods.each do |method_name|
    class_eval %Q{
      def #{method_name}(#{method_name})
        @#{method_name} = #{method_name} 
        self
      end
    }
  end

  def dump(opts = {}) 
    # initialize database connections
    init_db_connection

    # initialize opts
    opts = dump_opts opts  

    # before all callback
    before_dump opts

    tables_list.each do |database, tables| 
      tables.each do |table|

        # before each callback
        if opts[:before_each].respond_to? :call
          to_database, to_table = opts[:before_each].call(database, table)
        end
        to_database ||= database
        to_table ||= table 

        dump_table database, table, to_database, to_table, opts

        # after each callback
        if opts[:after_each].respond_to? :call
          opts[:after_each].call(database, table)
        end
      end
    end

    # after all callback
    after_dump opts

  end

  private

  def dump_opts(opts)
    {
      # it's used for "SET NAMES #{charset}"
      :charset => nil,

      # dump data or just table structure
      :with_data => true,

      # drop the table before do dump the table
      :drop_table_first => true,

      # number of rows per select
      :rows_per_select => 1000,

      # callbacks
      :before_all => nil,
      :after_all => nil,
      :before_each => nil,
      :after_each => nil
    }.merge(opts)
  end

  def before_dump(opts)
    # prepare dump 
    sqls = [
      "SET FOREIGN_KEY_CHECKS = 0",
      "SET UNIQUE_CHECKS = 0"
    ]
    sqls << "SET NAMES #{opts[:charset]}" if opts[:charset]
    sqls.each do |sql|
      run_sql sql, :on_connection => @to_db
    end
    opts[:before_all].call(@from_db, @to_db) if opts[:after_all].respond_to? :call
  end

  def after_dump(opts)
    # clean up 
    [
      "SET FOREIGN_KEY_CHECKS = 1",
      "SET UNIQUE_CHECKS = 1"
    ].each do |sql|
      run_sql sql, :on_connection => @to_db
    end
    opts[:after_all].call(@from_db, @to_db) if opts[:after_all].respond_to? :call 

    @from_db.disconnect
    @to_db.disconnect
  end

  def dump_table(from_database, from_table, to_database, to_table, opts = {})
    use_db from_database, :on_connection => @from_db

    create_database to_database

    create_table from_table, to_table, opts 

    dump_table_data @from_db[from_table.to_sym], @to_db[to_table.to_sym], opts
  end

  def create_database(to_database)
    begin
      use_db to_database, :on_connection => @to_db
    rescue Sequel::DatabaseError => e
      begin
        run_sql "CREATE DATABASE #{to_database}", :on_connection => @to_db
        use_db to_database, :on_connection => @to_db
      rescue Exception => e
        raise Mysql2MysqlException.new "create database #{to_database} failed\n  DSN info: #{@to_db}"
      end
    end
  end

  def create_table(from_table, to_table, opts)
    create_table_ddl = @from_db.fetch("SHOW CREATE TABLE #{from_table}").
      first[:'Create Table'].
      gsub("`#{from_table}`", "`#{to_table}`")

    run_sql "DROP TABLE IF EXISTS #{to_table}", :on_connection => @to_db if opts[:drop_table_first]
    if opts[:drop_table_first] or not @to_db.table_exists?(to_table.to_sym)
      begin
        run_sql create_table_ddl, :on_connection => @to_db
      rescue Exception => e
        raise Mysql2MysqlException.new "create table #{to_table} failed in the database #{to_database}\n  DSN info: #{@to_db}\n: message: #{e}"
      end
    end
  end

  def dump_table_data(from_db_table, to_db_table, opts)
    return unless opts[:with_data] 

    total = from_db_table.count
    limit = opts[:rows_per_select]
    limit = total if limit >= total

    columns = from_db_table.columns

    # temp variables
    rows = []
    offset = 0
    row = {}

    0.step(total - 1, limit) do |offset|
      rows = from_db_table.limit(limit, offset).collect do |row|
        row.values
      end

      to_db_table.import columns, rows
    end
  end

  def run_sql(sql, opts)
    opts[:on_connection].run sql 
  end

  def use_db(db, opts)
    run_sql "use #{db}", opts
  end

  def init_db_connection
    @from_db = db_connection @from
    @to_db = db_connection @to
  end

  def db_connection(dsn)
    dsn[:adapter] = 'mysql' if dsn.is_a? Hash
    Sequel.connect(dsn)
  end

  def tables_list
    raise Mysql2MysqlException.new 'No tables need to dump' if @tables.nil?
    filter_tables
  end

  def all_databases
    @from_db.fetch('SHOW DATABASES').collect do |row|
      row[:Database]
    end
  end

  def filter_tables 
    all_valid_tables = \
      if is_all? @tables
        all_databases.inject({}) do |all_tables, dbname|
          all_tables.merge dbname => get_tables_by_db(dbname)
        end
      else
        all_tables = {}
        all_databases.each do |dbname|
          @tables.each do |orig_dbname, orig_tbname|
            next unless is_eql_or_match?(orig_dbname, dbname)

            tables = get_tables_by_db dbname 

            if is_all? orig_tbname
              all_tables[dbname] = tables
              break
            end

            orig_tbnames = [orig_tbname] unless orig_tbname.is_a? Array
            tables = tables.find_all do |tbname|
              orig_tbnames.find do |orig_tbname|
                is_eql_or_match?(orig_tbname, tbname)
              end
            end

            all_tables[dbname] = tables
          end
        end

        all_tables
      end

    filter all_valid_tables
  end

  def is_eql_or_match?(origin, current)
    if origin.is_a? Regexp
      origin.match current 
    else
      origin.to_s == current.to_s
    end
  end

  def is_all?(items)
    [:all, '*'].include? items
  end

  def get_tables_by_db(dbname)
    use_db dbname, :on_connection => @from_db
    @from_db.tables
  end

  def filter(origin_tables)
    need_exclude = lambda do |origin, current|
      is_eql_or_match? origin, current 
    end

    return origin_tables if @exclude.nil?

    exclude_tables = case @exclude
                    when Symbol, String
                      {@exclude => '*'}
                    when Array
                      @exclude.inject({}) do |items, it|
                        items.merge it => '*'
                      end
                    when Hash 
                      @exclude
                    else
                      raise Mysql2MysqlException.new 'Invalid exclude parameters given'
                    end

    reject_table = lambda do |dbname, tbname|
      exclude_tables.each do |exclude_dbname, exclude_tbnames|
        next unless need_exclude.call(exclude_dbname, dbname)

        return true if is_all?(exclude_tbnames)

        exclude_tbnames = [exclude_tbnames] unless exclude_tbnames.is_a? Array
        return true if exclude_tbnames.find {|exclude_tbname|
          need_exclude.call(exclude_tbname, tbname)
        }
      end

      false
    end

    origin_tables.each do |dbname, tbnames|
      origin_tables[dbname] = tbnames.find_all do |tbname|
        not reject_table.call(dbname, tbname)
      end
    end

  end
end

class Mysql2MysqlException < Exception
end
