set :application, "patatat"
set :domain, CLI.ui.ask("Domain you are deploying to (IP Address or Hostname): ")
set :deploy_to, "/var/www/#{application}"
set :repository,  "git://github.com/mikeymckay/patatat.git"
set :scm, :git
set :keep_releases, 2
set :user, "deploy"
set :runner, "patatat"
set :use_sudo, :false

role :app, "#{domain}"
role :web, "#{domain}"
role :db,  "#{domain}", :primary => true

# == CONFIG ====================================================================
namespace :init do
  namespace :config do
    desc "Create shared configuration"
    task :patatat do
      if Capistrano::CLI.ui.ask("Create patatat configuration? (y/n): ") == 'y'
        set :twitter_name, Capistrano::CLI.ui.ask("twitter user: ")
				set :twitter_pass, Capistrano::CLI.password_prompt("twitter password: ")			
				patatat_configuration =<<-EOF
---
twitter:
  username: #{twitter_user}
  password: #{twitter_pass}
EOF
				sudo "mkdir -p #{shared_path}"
        sudo "chown deploy:deploy #{shared_path}"
				run "mkdir -p #{shared_path}/config"
				run "mkdir -p #{shared_path}/yoke"
				run "mkdir -p #{shared_path}/database"
				run "mkdir -p #{shared_path}/log"
				run "mkdir -p #{shared_path}/pids"
				put patatat_configuration, "#{shared_path}/config/patatat.conf"
		  end		
    end

    desc "Symlink shared configuration and data files to current"
    task :localize, :roles => [:app] do
      run "ln -nsf #{shared_path}/config/patatat.conf #{current_path}/config/patatat.conf"
      run "ln -nsf #{shared_path}/yoke #{current_path}/yoke"
      run "ln -nsf #{shared_path}/database #{current_path}/database"
      run "ln -nsf #{shared_path}/log #{current_path}/log"
      run "ln -nsf #{shared_path}/pids #{current_path}/pids"
    end 		
  end
end

# == DEPLOY ======================================================================
namespace :deploy do
  desc "Start patatat"
  task :start do
    run  "cd #{current_path} && sudo su - patatat script/patatat"
  end
  
  desc "Stop patatat"
  task :stop do
    puts "Not currently implemented"
  end
  
  desc "Restart patatat"
  task :restart do
    puts "Not currently implemented"
  end  
end

# == TASKS =====================================================================
after "deploy", "deploy:cleanup"
after "deploy:setup", "init:config:patatat"
after "deploy:symlink", "init:config:localize"

task :after_update_code do
  sudo "chown patatat:patatat #{release_path}/config -R"
  sudo "chown patatat:patatat #{current_path}/yoke -R"
  sudo "chown patatat:patatat #{current_path}/database -R"
  sudo "chown patatat:patatat #{current_path}/log -R"
  sudo "chown patatat:patatat #{current_path}/pids -R"
end