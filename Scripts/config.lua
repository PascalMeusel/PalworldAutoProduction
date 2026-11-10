-- Palworld AutoProduction settings.
return {
    ENABLED = true,

    -- Crafts queued per batch while AutoProduce is enabled for a station.
    BATCH_SIZE = 10,

    -- Refill check interval while at least one AutoProduce station is enabled.
    -- Food tracking and AFK meals use lightweight checks every five seconds.
    SCAN_INTERVAL_MS = 2000,

    -- Eat one real item from your own base's feed boxes when standing idle,
    -- hungry, and carrying no food (including the food pouch).
    BASE_AUTO_EAT = true,
    AFK_IDLE_SECONDS = 60,
    AFK_HUNGER_THRESHOLD = 0.5,
}
