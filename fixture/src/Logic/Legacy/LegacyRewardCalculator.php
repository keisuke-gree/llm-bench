<?php

declare(strict_types=1);

namespace Bench\Logic\Legacy;

/**
 * 旧報酬計算ロジック。新システムへの移行が完了するまでの間、
 * 一部の旧イベント・旧クエスト向けに残されている。
 */
final class LegacyRewardCalculator
{
    /**
     * 旧仕様のボーナスレートを適用する。
     */
    public function applyBonusRate(int $baseAmount, int $legacyCampaignId): int
    {
        $rateTable = [
            9001 => 1.2,
            9002 => 1.1,
        ];

        $rate = $rateTable[$legacyCampaignId] ?? 1.0;

        return (int) floor($baseAmount * $rate);
    }

    public function calculateLegacyBase(int $rank): int
    {
        return $rank * 80;
    }
}
