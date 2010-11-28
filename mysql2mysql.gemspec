require 'rubygems'
SPEC=Gem::Specification.new do |s|
	s.homepage = 'http://github.com/xianhuazhou'
	s.rubyforge_project = "mysql2mysql"
	s.name = 'mysql2mysql'
	s.version = '0.0.2'
	s.author = 'xianhua.zhou'
	s.email = 'xianhua.zhou@gmail.com'
	s.platform = Gem::Platform::RUBY  
	s.summary = "Dump table's structure and data between mysql servers and databases."
  s.files = %w(Changelog README.rdoc INSTALL lib/mysql2mysql.rb lib/mysql_2_mysql.rb spec/mysql_2_mysql_spec.rb)
	s.require_path = 'lib'
	s.has_rdoc = true
  s.add_dependency('sequel', '>= 3.13.0')
  s.add_development_dependency('rspec', '>= 2.0.1')
end
