# Roo Code: Windows Bootstrap Script Evolution
[ ] Implement Self-Aware Identity Parsing: Add logic to the script to inspect $MyInvocation and extract the GitHub username (dsjstc) directly from the raw.githubusercontent.com execution URL.

[ ] Automate Email Discovery: Using the extracted username, query the GitHub API (/users/ and /events/public) to retrieve the user's public or commit-associated email address.

[ ] Silent Tool Provisioning: Use winget to install Git, Bitwarden CLI, and Bitwarden Desktop. Use strict flags (--quiet, --accept-source-agreements, --accept-package-agreements) to ensure zero-click installation.

[ ] Automate Git Configuration: Silently set the global git config --global user.email using the email address discovered in the previous discovery step.

[ ] Orchestrate Bitwarden CLI:

Set bw config server to the standard vault.

Set the Bitwarden username to the discovered email.

Implement a check for bw status and handle the bw login / bw unlock flow, ensuring the BW_SESSION key is captured and exported to the User environment scope.

[ ] Enable SSH Infrastructure:

Ensure the native Windows ssh-agent service is set to 'Automatic' and is currently running.

Launch the Bitwarden Desktop app via bitwarden:// protocol to initialize the tray application.

[ ] IEX Compatibility & Robustness:

Add an admin-check guard at the script entry point (with a silent exit if not elevated).

Wrap all network and installation calls in Try/Catch blocks for "graceful failure" reporting.

Once everything else is working, recombine the final script to a single, robust .ps1 block optimized for iwr | iex execution.


# For later:

[]  serve-http is for local testing without having to push new bootstrap files to github for each test.  It's supposed to be a user mode http server.  It isn't working though.
