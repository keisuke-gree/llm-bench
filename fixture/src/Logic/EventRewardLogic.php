<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\EventDao;
use Bench\Model\UserContext;

/**
 * イベント報酬の付与を制御するクラス。
 */
final class EventRewardLogic
{
    public function __construct(
        private EventDao $eventDao,
        private RewardCalculator $rewardCalculator,
    ) {
    }

    /**
     * イベント基礎報酬にボーナスレートを適用して確定額を返す。
     */
    public function grantReward(int $eventId, UserContext $context, \DateTimeImmutable $now): int
    {
        $event = $this->eventDao->findById($eventId);
        $baseAmount = $event['baseReward'];

        $confirmedAmount = $this->rewardCalculator->applyBonusRate($baseAmount, $context, $now);

        $this->eventDao->recordEntry($eventId, $context->userId);

        return $confirmedAmount;
    }
}
