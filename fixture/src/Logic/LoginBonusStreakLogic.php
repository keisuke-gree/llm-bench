<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\LoginBonusDao;

/**
 * ログイン連続日数に関する補助的な業務ロジックを担うクラス。
 */
final class LoginBonusStreakLogic
{
    public function __construct(private LoginBonusDao $loginBonusDao)
    {
    }

    /**
     * 連続ログイン日数から達成済みマイルストーンの一覧を返す。
     *
     * @return list<int>
     */
    public function resolveMilestones(int $streakDays): array
    {
        $milestones = [3, 7, 14, 30];
        $achieved = [];

        foreach ($milestones as $milestone) {
            if ($streakDays >= $milestone) {
                $achieved[] = $milestone;
            }
        }

        return $achieved;
    }
}
