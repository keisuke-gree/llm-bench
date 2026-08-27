<?php

declare(strict_types=1);

namespace Bench\Logic\Legacy;

/**
 * 旧システム向けの夜間バッチ処理。
 */
final class LegacyBatchLogic
{
    private const DEFAULT_LEGACY_BASE = 50;
    private const DEFAULT_LEGACY_CAMPAIGN_ID = 9001;

    public function __construct(private LegacyRewardCalculator $legacyRewardCalculator)
    {
    }

    /**
     * @param list<int> $legacyUserIds
     */
    public function runNightlyGrant(array $legacyUserIds): int
    {
        $processed = 0;

        foreach ($legacyUserIds as $legacyUserId) {
            $this->legacyRewardCalculator->applyBonusRate(
                self::DEFAULT_LEGACY_BASE,
                self::DEFAULT_LEGACY_CAMPAIGN_ID,
            );
            $processed++;
        }

        return $processed;
    }
}
