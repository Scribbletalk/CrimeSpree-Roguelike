-- DEBUG keybind: fully reset the local CSR (roguelike) run with NO rewards. Strip before release.
-- Mirrors End Spree's teardown (reset_mp_earnings + end_run) but SKIPS the payout step, so
-- nothing is granted. Local state only; does not touch vanilla Crime Spree.

local mgr = managers and managers.csr
if not mgr then
	return
end

-- Discard banked guest earnings (bucket B) so a later End Spree can't claim them.
if mgr.reset_mp_earnings then
	mgr:reset_mp_earnings()
end
-- Deactivate run + wipe inventory + save. No reward computation, no claim node.
mgr:end_run()
csr_log("[CSR][DEBUG] reset_run: local CSR run cleared with no rewards")
