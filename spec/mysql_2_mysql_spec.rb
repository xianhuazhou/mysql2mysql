require File.dirname(__FILE__) + '/../lib/mysql_2_mysql.rb'

require 'sequel'
$from_dsn = 'mysql://localhost:3306/test?user=root&password='
$to_dsn = 'mysql://127.0.0.1:3307/test?user=root&password='

def disconnect(m2m)
    m2m.instance_variable_get('@from_db').disconnect
    m2m.instance_variable_get('@to_db').disconnect
end

describe Mysql2Mysql, 'initialize' do
  it "can initialize some parameters" do

    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn, :tables => {:test => '*'}, :exclude => {}
    m2m.instance_variable_get('@from').should == $from_dsn
    m2m.instance_variable_get('@to').should == $to_dsn
    m2m.instance_variable_get('@tables').should == {:test => '*'} 
    m2m.instance_variable_get('@exclude').should == {} 

    m2m.from($from_dsn + '1').instance_variable_get('@from').should == $from_dsn + '1'
    m2m.to($to_dsn + '1').instance_variable_get('@to').should == $to_dsn + '1'
  end
end 

describe Mysql2Mysql, 'dump_opts' do
  it "should have some pre-defined options" do
    m2m = Mysql2Mysql.new
    m2m.send(:dump_opts, {}).should == {   
      :charset => nil,
      :with_data => true,
      :drop_table_first => true,
      :rows_per_select => 1000,
      :before_all => nil,
      :after_all => nil,
      :before_each => nil,
      :after_each => nil 
    }

   m2m.send(:dump_opts, {:charset => 'utf8'})[:charset].should == 'utf8' 
   m2m.send(:dump_opts, {:before_all => lambda{}})[:before_all].should == lambda{} 
  end
end

describe Mysql2Mysql, 'before_dump' do
  it "can change some mysql variables" do
    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn 
    m2m.send :init_db_connection
    m2m.send(:before_dump, m2m.send(:dump_opts, {:charset => 'utf8'}))
    to_db = m2m.instance_variable_get('@to_db')

    to_db.fetch("SHOW VARIABLES LIKE 'FOREIGN_KEY_CHECKS'").first[:Value].should == 'OFF'
    to_db.fetch("SHOW VARIABLES LIKE 'UNIQUE_CHECKS'").first[:Value].should == 'OFF'
    to_db.fetch("SHOW VARIABLES LIKE 'CHARACTER_SET_CLIENT'").first[:Value].should == 'utf8'
    to_db.fetch("SHOW VARIABLES LIKE 'CHARACTER_SET_CONNECTION'").first[:Value].should == 'utf8'

    disconnect(m2m)
  end

  it "can execute the code hook 'before_all'" do
    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn 
    m2m.send :init_db_connection
    $mysql_expr = nil
    m2m.send(:before_dump, m2m.send(:dump_opts, {:before_all => lambda{|from_db, to_db|
      $mysql_expr = from_db.fetch("SELECT 1+1 AS num").first[:num]
    }}))
    $mysql_expr.should == 2
  end
end

describe Mysql2Mysql, 'after_dump' do
  it "can revert some mysql variable" do
    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn 
    m2m.send :init_db_connection
    m2m.send(:after_dump, m2m.send(:dump_opts, {}))
    to_db = m2m.instance_variable_get('@to_db')

    to_db.fetch("SHOW VARIABLES LIKE 'FOREIGN_KEY_CHECKS'").first[:Value].should == 'ON'
    to_db.fetch("SHOW VARIABLES LIKE 'UNIQUE_CHECKS'").first[:Value].should == 'ON'

    disconnect(m2m)
  end

  it "can execute the code hook 'after_all'" do
    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn 
    m2m.send :init_db_connection
    $mysql_expr = nil
    m2m.send(:after_dump, m2m.send(:dump_opts, {:after_all => lambda{|from_db, to_db|
      $mysql_expr = from_db.fetch("SELECT 1+1 AS num").first[:num]
    }}))
    $mysql_expr.should == 2
    disconnect(m2m)
  end
end

describe Mysql2Mysql, 'create_database' do
  it "can create a new database on the target mysql server" do
    db_name = 'db_m2m'
    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn 
    m2m.send :init_db_connection

    to_db = m2m.instance_variable_get('@to_db')
    to_db.run "DROP DATABASE IF EXISTS #{db_name}"

    m2m.send :create_database, db_name 
    to_db.fetch("SHOW DATABASES").all.collect{|row|row.values.first}.should include(db_name)

    # do it again
    m2m.send :create_database, db_name 
    to_db.fetch("SHOW DATABASES").all.collect{|row|row.values.first}.should include(db_name)

    # clean up
    to_db.run "DROP DATABASE #{db_name}"
    disconnect(m2m)
  end
end

describe Mysql2Mysql, 'create_table' do
  it "can create a new table on the target mysql server according to the source mysql server" do
    db_name = 'db_m2m'
    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn 
    m2m.send :init_db_connection

    from_db = m2m.instance_variable_get('@from_db')
    to_db = m2m.instance_variable_get('@to_db')

    from_db.run "DROP DATABASE IF EXISTS #{db_name}"
    to_db.run "DROP DATABASE IF EXISTS #{db_name}"

    from_db.run "CREATE DATABASE #{db_name}"
    from_db.run "USE #{db_name}"
    from_db.run "CREATE TABLE t(id INT)"

    # use the same table name
    m2m.send :create_database, db_name
    m2m.send :create_table, 't', 't', m2m.send(:dump_opts, {})
    to_db.tables.should include(:t)

    # use different table name
    m2m.send :create_table, 't', 't2', m2m.send(:dump_opts, {})
    to_db.tables.should include(:t2)

    from_db.run "DROP DATABASE #{db_name}"
    to_db.run "DROP DATABASE #{db_name}"

    disconnect(m2m)
  end
end

describe Mysql2Mysql, 'dump_table_data' do
  it "can copy table's data from one server to another server" do
    db_name = 'db_m2m'
    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn 
    m2m.send :init_db_connection

    from_db = m2m.instance_variable_get('@from_db')
    to_db = m2m.instance_variable_get('@to_db')

    from_db.run "DROP DATABASE IF EXISTS #{db_name}"
    to_db.run "DROP DATABASE IF EXISTS #{db_name}"

    from_db.run "CREATE DATABASE #{db_name}"
    from_db.run "USE #{db_name}"
    from_db.run "CREATE TABLE t(id INT)"

    m2m.send :create_database, db_name
    m2m.send :create_table, 't', 't', m2m.send(:dump_opts, {})

    # 1 row
    from_db.run "INSERT INTO t(id) VALUES(1)"
    m2m.send :dump_table_data, from_db[:t], to_db[:t], m2m.send(:dump_opts, {})
    to_db[:t].first.should == {:id => 1}

    # 2 rows now
    from_db.run "INSERT INTO t(id) VALUES(2)"
    m2m.send :dump_table_data, from_db[:t], to_db[:t], m2m.send(:dump_opts, {})
    to_db[:t].all == [{:id => 1}, {:id => 2}]

    # 2010 rows
    from_db.run "TRUNCATE TABLE t"
    to_db.run "TRUNCATE TABLE t"
    1.upto(2010) do |i|
      from_db[:t].insert :id => i
    end
    m2m.send :dump_table_data, from_db[:t], to_db[:t], m2m.send(:dump_opts, {})
    to_db[:t].count.should == 2010

    from_db.run "DROP DATABASE #{db_name}"
    to_db.run "DROP DATABASE #{db_name}"

    disconnect(m2m)
  end
end

describe Mysql2Mysql, 'convert_tables' do
  it "should support several different types" do
    m2m = Mysql2Mysql.new
    m2m.send(:convert_tables, 'db_m2m' => '*').should == {'db_m2m' => '*'}
    m2m.send(:convert_tables, 'db_m2m').should == {'db_m2m' => '*'}
    m2m.send(:convert_tables, :db_m2m).should == {'db_m2m' => '*'}
    m2m.send(:convert_tables, [:db1, :db2]).should == {'db1' => '*', 'db2' => '*'}
    m2m.send(:convert_tables, {:db1 => ['tb1', 'tb2'], :db2 => '*'}).should == {:db1 => ['tb1', 'tb2'], :db2 => '*'}
  end
end

describe Mysql2Mysql do
  it "can clone one database" do
    db_name = 'db_m2m'

    sequel = Sequel.connect $from_dsn
    sequel.run "CREATE DATABASE #{db_name}"
    sequel.run "USE #{db_name}"
    sequel.run "CREATE TABLE t(id INT)"

    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn, :tables => {db_name => '*'}
    m2m.dump
    from_db = m2m.instance_variable_get('@from_db')
    to_db = m2m.instance_variable_get('@to_db')
    to_db.fetch("SHOW DATABASES").all.collect{|row|row.values.first}.should include(db_name)

    from_db.run "DROP DATABASE #{db_name}"
    to_db.run "DROP DATABASE #{db_name}"
    sequel.disconnect
    disconnect(m2m)
  end

  it "can clone two databases" do
    db1_name = 'db_m2m_a'
    db2_name = 'db_m2m_b'

    sequel = Sequel.connect $from_dsn
    sequel.run "DROP DATABASE IF EXISTS #{db1_name}"
    sequel.run "DROP DATABASE IF EXISTS #{db2_name}"
    sequel.run "CREATE DATABASE #{db1_name}"
    sequel.run "CREATE DATABASE #{db2_name}"
    sequel.run "USE #{db1_name}"
    sequel.run "CREATE TABLE t1(id INT)"
    sequel.run "USE #{db2_name}"
    sequel.run "CREATE TABLE t2(id INT)"

    m2m = Mysql2Mysql.new :from => $from_dsn, :to => $to_dsn, :tables => [db1_name, db2_name] 
    m2m.dump
    from_db = m2m.instance_variable_get('@from_db')
    to_db = m2m.instance_variable_get('@to_db')
    to_db.fetch("SHOW DATABASES").all.collect{|row|row.values.first}.should include(db1_name)
    to_db.fetch("SHOW DATABASES").all.collect{|row|row.values.first}.should include(db2_name)
    to_db.run "use #{db1_name}"
    to_db.tables.should include(:t1)
    to_db.run "use #{db2_name}"
    to_db.tables.should include(:t2)

    from_db.run "DROP DATABASE #{db1_name}"
    from_db.run "DROP DATABASE #{db2_name}"
    to_db.run "DROP DATABASE #{db1_name}"
    to_db.run "DROP DATABASE #{db2_name}"
    sequel.disconnect
    disconnect(m2m)
  end
end
