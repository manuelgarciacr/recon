
# RECON.SH

```bash
Usage: ./recon.sh [options] <workspace>

<workspace>: Workspace name for recon-ng and folder with the results. It cannot start with a hyphen.

options:
  --clean-workspace      Remove data from previous runs if any.
  --domain DOMAIN, -d    Domain
  --help, -h             Show command line options
  --log, -l              Log file. By default 'recon.log'
  --modules, -m          Modules to use: 'fierce, dnsrecon, rn_certificate_transparency, rn_hackertarget, rn_brute_hosts'. If none are declared, all will be used.
  --only-active, -a      Run only active scans
  --only-passive, -s     Run only passive scans (silent)
  --reuse_workspace      Reuse data from previous runs if any. The folder and the workspace must exist
  --verbose, -v			 Verbose

Examples:
  ./recon.sh -d example.com -m fierce,rn_hackertarget --only-passive myworkspace 
  # Workspace myworkspace, domain example.com, uses only the module rn_hackertarget because fierce is considered active
  ./recon.sh --domain example.com myworkspace --reuse_workspace
  # Domain example.com, workspace myworkspace, reuse data from previous runs
```

TODO: Unit tests
TODO: Add theHarvester and DNSDumpster
TODO: Summarize log data
