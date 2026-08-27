<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\EventRewardLogic;
use Bench\Logic\RewardCalculator;
use Bench\Model\UserContext;

/**
 * イベント関連のHTTPリクエストを処理するコントローラー。
 */
final class EventController
{
    public function __construct(
        private EventRewardLogic $eventRewardLogic,
        private RewardCalculator $rewardCalculator,
    ) {
    }

    public function grantReward(int $eventId, UserContext $context): array
    {
        $now = new \DateTimeImmutable();
        $amount = $this->eventRewardLogic->grantReward($eventId, $context, $now);

        return ['eventId' => $eventId, 'rewardAmount' => $amount];
    }

    /**
     * イベント参加前にボーナス適用後の見込み額をシミュレーションする。
     */
    public function simulateBonus(int $baseAmount, UserContext $context): array
    {
        $now = new \DateTimeImmutable();
        $amount = $this->rewardCalculator->applyBonusRate($baseAmount, $context, $now);

        return ['simulatedAmount' => $amount];
    }
}
