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
        run <<-CMD
				  mkdir -p #{shared_path}/config &&
				  mkdir -p #{shared_path}/yoke &&
				  mkdir -p #{shared_path}/database &&
				  mkdir -p #{shared_path}/log &&
				  mkdir -p #{shared_path}/pids
        CMD  
				put patatat_configuration, "#{shared_path}/config/patatat.conf"
		  end		
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

  desc "Finalize the update"
  task :finalize_update, :except => { :no_release => true } do
    run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)
    run <<-CMD
      rm -rf #{latest_release}/log #{latest_release}/tmp/pids &&
      mkdir -p #{latest_release}/tmp &&
      ln -s #{shared_path}/log #{latest_release}/log &&
      ln -s #{shared_path}/pids #{latest_release}/tmp/pids
    CMD
  end  

end

# == TASKS =====================================================================
after "deploy", "deploy:cleanup"
after "deploy:setup", "init:config:patatat"

task :after_update_code do
  run <<-CMD
    ln -nsf #{shared_path}/config/patatat.conf #{release_path}/config/patatat.conf &&
    ln -nsf #{shared_path}/yoke #{release_path}/yoke &&
    ln -nsf #{shared_path}/database #{release_path}/database &&
    ln -nsf #{shared_path}/log #{release_path}/log && 
    ln -nsf #{shared_path}/pids #{release_path}/pids 
  CMD  

  sudo "chown patatat:patatat #{release_path}/config -R"
  sudo "chown patatat:patatat #{release_path}/yoke -R"
  sudo "chown patatat:patatat #{release_path}/database -R"
  sudo "chown patatat:patatat #{release_path}/log -R"
  sudo "chown patatat:patatat #{release_path}/tmp/pids -R"
end