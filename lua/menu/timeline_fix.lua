-- Crime Spree Roguelike - Timeline marker overflow fix
-- At high CS ranks (1000+), vanilla draws too many future modifier
-- milestones on the progress bar, causing overlapping text.
-- This PostHook hides markers that don't fit.

if not RequiredScript then
	return
end

local MAX_VISIBLE_MARKERS = 4

Hooks:PostHook(CrimeSpreeResultTabItem, "_create_timeline", "CSR_TimelineFix", function(self)
	if not self._timeline or not self._timeline.markers then
		return
	end

	local markers = self._timeline.markers
	if #markers <= MAX_VISIBLE_MARKERS then
		return
	end

	-- Hide all markers beyond the limit
	for i = MAX_VISIBLE_MARKERS + 1, #markers do
		local entry = markers[i]
		-- entry = {level, {ticket_text, marker_text}}
		if entry and entry[2] then
			local elements = entry[2]
			for _, el in ipairs(elements) do
				if el and el.set_visible then
					el:set_visible(false)
				end
			end
		end
	end

	-- NOTE: vanilla marker lines are anonymous rects (no name param),
	-- so they cannot be hidden by child lookup. They are 3px wide with
	-- alpha 0.4, barely visible — not worth the complexity to remove.
end)
