<?php

declare(strict_types=1);

namespace Bench\Logic\Legacy;

/**
 * 旧イベントシステム向けの報酬付与ロジック。
 */
final class LegacyEventLogic
{
    public function __construct(private LegacyRewardCalculator $legacyRewardCalculator)
    {
    }

    public function grantLegacyReward(int $baseAmount, int $legacyCampaignId): int
    {
        return $this->legacyRewardCalculator->applyBonusRate($baseAmount, $legacyCampaignId);
    }
}
