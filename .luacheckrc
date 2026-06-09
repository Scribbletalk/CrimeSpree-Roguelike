-- Luacheck config for Crime Spree Roguelike
std = "lua51"
max_line_length = false

-- Truly immutable primitives and PD2-extended standard library fields
read_globals = {
    -- PD2 math / constructors
    "Color", "Vector3", "Rotation", "Idstring", "mvector3",
    -- PD2 extensions to standard libraries (not in Lua 5.1 std)
    math = { fields = { "round", "lerp", "rand", "clamp", "UP" } },
    table = { fields = { "contains", "size" } },
    -- PD2 async / coroutine helpers
    "callback", "alive", "wait", "over", "DelayedCalls", "debug_pause",
    -- PD2 utilities
    "deep_clone", "clone",
    -- PD2 platform
    "NOT_WIN_32", "XAudio",
    -- SuperBLT / LuaJIT extras
    "json", "utf8",
}

-- Everything else: PD2 engine, vanilla classes, and CSR's own globals.
-- In PD2 modding we routinely extend vanilla classes (add methods, write fields),
-- so read_globals would produce false positives for all of them.
globals = {
    -- SuperBLT
    "RequiredScript", "ModPath", "SavePath", "log", "file", "Hooks", "LuaNetworking",
    "BeardLib",
    -- PD2 class system
    "class",
    -- PD2 global state
    "managers", "tweak_data", "Global",
    -- PD2 engine singletons
    "Application", "World", "Network", "Input", "DB", "Workspace", "Draw",
    "SystemFS", "TimerManager", "PackageManager", "DynamicResourceManager",
    "game_state_machine", "GameSetup", "Setup", "setup",
    "SoundDevice", "LocalizationManager", "SystemInfo",
    -- PD2 AI / placement
    "is_placement_in_seg_walkable", "is_placement_los_from_player",
    -- PD2 telemetry
    "Telemetry", "TelemetryConst",
    -- PD2 UI primitives
    "BoxGuiObject", "WalletGuiObject", "ScrollablePanel", "TimerGui",
    -- PD2 menu system
    "MenuBackdropGUI", "MenuGuiComponentGeneric", "MenuGuiItem", "MenuHelper",
    "MenuCallbackHandler", "MenuComponentManager", "MenuManager",
    "MissionBriefingGui", "StageEndScreenGui", "StatsTabItem",
    "SkirmishBriefingProgress",
    -- PD2 ingame UI
    "IngameContractGui",
    -- PD2 HUD
    "HudIconsTweakData", "HUDInteraction", "HUDManager", "HUDMissionBriefing",
    "HUDStageEndCrimeSpreeScreen", "HUDStageEndScreen", "HUDTeammate",
    -- PD2 player / weapon / enemy
    "BaseNetworkSession",
    "BaseInteractionExt", "UseInteractionExt", "InteractionTweakData",
    "PlayerBase", "HuskPlayerBase", "PlayerDamage", "PlayerManager", "PlayerStandard", "StatisticsManager",
    "PlayerMovement", "HuskPlayerMovement",
    "CopDamage", "CivilianDamage", "TeamAIDamage",
    "NewRaycastWeaponBase", "RaycastWeaponBase", "NewNPCRaycastWeaponBase", "SentryGunWeapon",
    "AmmoClip", "GageAssignmentBase", "WeaponDescription",
    -- PD2 AI / mission
    "GroupAIStateBase", "GroupAIStateBesiege", "IngameWaitingForPlayersState",
    "TeamAILogicIdle", "CopLogicTravel",
    "MissionEndState", "MissionManager",
    "ElementAreaTrigger", "ElementSpawnEnemyDummy",
    -- PD2 economy / black market
    "MoneyManager", "BlackMarketGui", "BlackMarketManager",
    -- PD2 crime spree (vanilla base classes CSR extends)
    "CrimeNetGui", "GamemodeCrimeSpree", "CrimeSpreeManager", "CrimeSpreeTweakData",
    "CrimeSpreeBlackMarketMenuComponent", "CrimeSpreeBlackMarketShopPage",
    "CrimeSpreeContractBoxGui",
    "CrimeSpreeCopierInteractionExt", "CrimeSpreeScrapperInteractionExt",
    "CrimeSpreeLogbookMenuComponent", "CrimeSpreeModifierDetailsPage",
    "MenuCrimeNetContractInitiator", "MenuCrimeNetCrimeSpreeContractInitiator",
    -- PD2 crime spree modifier classes CSR mutates by name
    "ModifierAssaultExtender", "ModifierHeavySniper",
    -- PD2 base modifier class + CSR's own custom modifier classes
    "BaseModifier", "ModifierCSRPagerResponse",
    -- CSR core manager
    "CSRGameManager",
    -- CSR UI components
    "CSRMenuComponent", "CSRMissionsMenuComponent", "CSRMissionBriefing",
    "CSRHUDStageEndScreen", "CSRStageEndScreenGui", "CSRCrimeSpreeResultTabItem",
    -- CSR UI widgets
    "CSRSidebar", "CSRSidebarItem", "CSRSidebarSeparator",
    "CSRMissionButton", "CSRStartButton",
    "CSRItemSelectionComponent", "CSRItemSelectionButton", "CSRItemSelectionActionButton",
    "CSROwnedItemsStrip",
    -- CSR contract
    "CSRContractMenuComponent", "MenuCSRContractInitiator",
    -- CSR module tables / singletons
    "CSR_Shop", "CSR_LogbookProgress", "CSR_MP",
    -- CSR global helpers
    "csr_log",
    -- CSR callbacks
    "CSR_CloseItemSelection",
}

ignore = {
    "211",  -- unused function (common in PD2 hook stubs)
    "212",  -- unused argument (PD2 callbacks always receive self/t/dt)
    "213",  -- unused loop variable
    "611", "612", "613", "614",  -- whitespace (StyLua handles this)
}
