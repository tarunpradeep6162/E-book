mkdir -p platform
cd platform
git init

# Separate lifecycles so releases cannot silently absorb infrastructure changes.
mkdir -p apps/{api,worker} infra/{bootstrap,modules}
mkdir -p infra/environments/{dev,staging,prod}/{aws,azure}

# Commit configuration contracts, never recovered data or secret values.
mkdir -p config/environments deploy/{compose,kubernetes}
mkdir -p ci docs/{architecture,runbooks} tests/architecture

touch README.md docs/architecture/{environment-matrix,dependency-map,threat-model,acceptance-criteria}.md
touch docs/runbooks/{restore-database,restore-jenkins,emergency-access}.md
