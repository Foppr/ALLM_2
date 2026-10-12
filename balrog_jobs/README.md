# BALROG sweep: 5 models x 6 envs = 30 jobs

```
config.sh          <- edit: paths, models, episode budget
keys.env.example   <- copy to ~/balrog_keys.env, fill in, chmod 600
make_jobs.sh       <- (re)generates jobs/*.sh from config.sh
jobs/*.sh          <- the 30 job files (each runnable on its own: bash jobs/nim_babyai.sh)
run_all.sh         <- THE one command
run_lane.sh        <- runs one model's 6 envs in sequence
status.sh / stop_all.sh
logs/  state/      <- created at runtime
```

## Setup (once, on the server)
```bash
cp keys.env.example ~/balrog_keys.env && nano ~/balrog_keys.env && chmod 600 ~/balrog_keys.env
# in BALROG/SECRETS: leave OPENAI_API_KEY= empty
nano config.sh      # check BALROG_DIR, CONDA_ENV, model IDs
./make_jobs.sh      # regenerate after every config.sh change
```

## Run
```bash
./run_all.sh              # everything (5 lanes in parallel, 6 envs each in sequence)
./run_all.sh nim mistral  # just some models
./status.sh               # running / done / failed
tail -f logs/nim_babyai.log
./stop_all.sh
```
Re-running `./run_all.sh` skips jobs already marked done, so failed or stopped jobs are retried.
Results: `$RESULTS_DIR/<model>/<env>/<timestamp>_.../` (summary.json, eval.log, per-episode json).
