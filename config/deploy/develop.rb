set :stage, :dev

# don't specify db as it's not needed for unipept
server 'naos.ugent.be', user: 'dodona', roles: [:web, :app, :db], ssh_options: {
  port: 4840
}

set :branch, 'develop'
set :rails_env, :development