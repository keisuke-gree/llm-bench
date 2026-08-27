<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\RankingDao;

/**
 * ランキング報酬に関する補助的な業務ロジックを担うクラス。
 */
final class RankingRewardLogic
{
    public function __construct(private RankingDao $rankingDao)
    {
    }

    /**
     * 順位に応じた報酬ランクを決定する。
     */
    public function resolveRewardRank(int $position): string
    {
        return match (true) {
            $position === 1 => 'S',
            $position <= 10 => 'A',
            $position <= 100 => 'B',
            default => 'C',
        };
    }
}
