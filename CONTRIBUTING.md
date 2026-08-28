# Contributing

Thanks for helping improve Bitcoin Bar for Omarchy.

## Development

1. Use an up-to-date Omarchy installation.
2. Keep packaged Omarchy files under `/usr/share/omarchy/` read-only.
3. Make changes in your checkout and run:

   ```bash
   ./tests/run.sh
   ```

4. For live testing, copy the checkout to `~/.config/omarchy/plugins/nmorton.bitcoin/`; do not use symlinks.
5. Verify the summary, block-details, and price-details layouts before submitting a pull request.

Keep changes focused and explain user-visible behavior in the pull request. New network requests must use fixed HTTPS endpoints, bounded timeouts, and no user-controlled shell interpolation.
