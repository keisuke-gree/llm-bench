<?php

declare(strict_types=1);

namespace Bench\Logic\Batch;

use Bench\Dao\UserDao;
use Bench\Logic\RewardCalculator;
use Bench\Model\UserContext;

/**
 * 毎日実行されるログインボーナス付与バッチ処理。
 */
final class DailyBonusBatch
{
    private const DAILY_BASE_AMOUNT = 50;

    public function __construct(
        private UserDao $userDao,
        private RewardCalculator $rewardCalculator,
    ) {
    }

    /**
     * アクティブユーザー全員に日次ボーナスを付与する。
     */
    public function run(\DateTimeImmutable $now): int
    {
        $userIds = $this->userDao->findActiveUserIds();
        $processed = 0;

        foreach ($userIds as $userId) {
            $context = $this->buildContext($userId);
            $this->rewardCalculator->applyBonusRate(self::DAILY_BASE_AMOUNT, $context, $now);
            $processed++;
        }

        return $processed;
    }

    private function buildContext(int $userId): UserContext
    {
        $userInfo = $this->userDao->findById($userId);

        return new UserContext(userId: $userId, level: $userInfo['level']);
    }
}
