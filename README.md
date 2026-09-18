
# recon.sh

```text
Usage: ./recon.sh [options] <workspace>

<workspace>: Workspace name for recon-ng and folder with the results. It cannot 
    start with a hyphen.
If no domain and no IPs are provided, scans the current network.

options:
  --active-recon-mode, -a   Run active host discovery modules
  --clean-workspace         Remove data from previous runs if any.
  --domain DOMAIN, -d       Domain. If defined, perimeter domain searches are
                                performed.
  --help, -h                Show command line options.
  --log, -l                 Log file. By default 'recon.log'.
  --modules, -m             Modules to use: 'dnsdumpster, theharvester, 
                                fierce, dnsrecon, rn_certificate_transparency, 
                                rn_hackertarget, rn_brute_hosts'. If none is 
                                declared, all modules can be used.
  --noisy-scan-mode, -n     Runs active port scans in noisy mode. (see --stealth-scan-mode)
  --range, -r               IP range as comma separated values, CIDR or first-
                                last ip. If IPs are found or defined,
                                port scanners will proceed.
  --reuse_workspace         Reuse data from previous runs if any. The folder
                                and the workspace must exist.
  --stealth-scan-mode, -s   Runs active port scans in stealth mode. (see --noisy-scan-mode)
  --verbose, -v             Verbose.

Examples:
  ./recon.sh -d example.com -m fierce,rn_hackertarget myworkspace 
  # Workspace myworkspace, domain example.com, uses only the module 
      rn_hackertarget because fierce is considered active and needs 
      the --active flag
  ./recon.sh --domain example.com myworkspace --reuse_workspace
  # Domain example.com, workspace myworkspace, reuse data from previous runs
```

TODO: Unit tests
TODO: Add theHarvester
TODO: Summarize log data
TODO: Multiple domain option. DNSDumpster must have 2'' delay. Plus membership has pagination. See [DNSDumpster Developer Documentation](https://dnsdumpster.com/developer/)
TODO: Add Spyse
TODO: Remove --stealth-scan-mode
TODO: Range IPs parameter
TODO: Ports parameter
TODO: Force module

