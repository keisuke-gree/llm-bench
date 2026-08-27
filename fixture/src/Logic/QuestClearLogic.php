<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\QuestDao;
use Bench\Model\UserContext;

/**
 * クエストクリア時の報酬付与を制御するクラス。
 */
final class QuestClearLogic
{
    private const SUMMER_CAMPAIGN_ID = 3;

    public function __construct(
        private QuestDao $questDao,
        private RewardCalculator $rewardCalculator,
    ) {
    }

    /**
     * クエストクリア報酬を計算して確定させる。
     */
    public function clear(int $questId, UserContext $context, \DateTimeImmutable $now): int
    {
        $quest = $this->questDao->findById($questId);
        $baseAmount = $this->rewardCalculator->calculateBaseAmount($quest['rank'], $quest['clearCount']);

        $amount = $this->rewardCalculator->applyBonusRate($baseAmount, $context, $now);

        if ($context->campaignId === self::SUMMER_CAMPAIGN_ID) {
            // 夏季キャンペーン専用の付帯処理フラグを立てる（加算処理は現状なし）
            $amount = $this->applySummerSpecialFlag($amount);
        }

        $this->questDao->incrementClearCount($questId);

        return $amount;
    }

    private function applySummerSpecialFlag(int $amount): int
    {
        return $amount;
    }
}
