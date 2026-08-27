<?php

declare(strict_types=1);

namespace Bench\Logic\Legacy;

/**
 * 旧クエストシステム向けの報酬付与ロジック。
 */
final class LegacyQuestLogic
{
    public function __construct(private LegacyRewardCalculator $legacyRewardCalculator)
    {
    }

    public function clearLegacyQuest(int $questRank, int $legacyCampaignId): int
    {
        $base = $this->legacyRewardCalculator->calculateLegacyBase($questRank);

        return $this->legacyRewardCalculator->applyBonusRate($base, $legacyCampaignId);
    }
}
