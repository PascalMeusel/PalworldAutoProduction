-- Palworld AutoProduction settings.
return {
    ENABLED = true,

    -- Default crafts per batch. Override per station in Bases > Production.
    BATCH_SIZE = 10,

    -- Coalesced production/pickup notifications supplement normal polling.
    -- Set false to compare performance or troubleshoot a game/loader build.
    FAST_REFILL = true,

    -- Refill check interval while at least one AutoProduce station is enabled.
    -- Food tracking and AFK meals use lightweight checks every five seconds.
    SCAN_INTERVAL_MS = 2000,

    -- Eat one real item from your own base's feed boxes when standing idle,
    -- hungry, and carrying no food (including the food pouch).
    BASE_AUTO_EAT = true,
    AFK_IDLE_SECONDS = 60,
    AFK_HUNGER_THRESHOLD = 0.5,
}
