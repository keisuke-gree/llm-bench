<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\UserDao;

/**
 * ユーザー経験値に関する補助的な業務ロジックを担うクラス。
 */
final class UserExperienceLogic
{
    public function __construct(private UserDao $userDao)
    {
    }

    /**
     * レベルアップに必要な残り経験値を算出する。
     */
    public function resolveRemainingExperience(int $currentExperience, int $nextLevelThreshold): int
    {
        return max(0, $nextLevelThreshold - $currentExperience);
    }
}
