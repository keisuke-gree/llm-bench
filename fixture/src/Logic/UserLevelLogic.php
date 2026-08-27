<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\UserDao;

/**
 * ユーザーレベルに関する補助的な業務ロジックを担うクラス。
 */
final class UserLevelLogic
{
    public function __construct(private UserDao $userDao)
    {
    }

    private const EXPERIENCE_PER_LEVEL = 1000;

    /**
     * 累計経験値から現在のレベルを算出する。
     */
    public function resolveLevel(int $totalExperience): int
    {
        return intdiv($totalExperience, self::EXPERIENCE_PER_LEVEL) + 1;
    }
}
