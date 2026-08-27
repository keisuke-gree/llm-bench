<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\AchievementDao;

/**
 * アチーブメント進捗に関する補助的な業務ロジックを担うクラス。
 */
final class AchievementProgressLogic
{
    public function __construct(private AchievementDao $achievementDao)
    {
    }

    /**
     * 進捗値が目標値に到達したかどうかを判定する。
     */
    public function isCompleted(int $progressValue, int $targetValue): bool
    {
        return $progressValue >= $targetValue;
    }

    public function calculateProgressRate(int $progressValue, int $targetValue): float
    {
        if ($targetValue <= 0) {
            return 0.0;
        }

        return min(1.0, $progressValue / $targetValue);
    }
}
