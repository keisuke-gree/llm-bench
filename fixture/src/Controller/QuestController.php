<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\QuestClearLogic;
use Bench\Logic\RewardCalculator;
use Bench\Model\UserContext;

/**
 * クエスト関連のHTTPリクエストを処理するコントローラー。
 */
final class QuestController
{
    public function __construct(
        private QuestClearLogic $questClearLogic,
        private RewardCalculator $rewardCalculator,
    ) {
    }

    public function clear(int $questId, UserContext $context): array
    {
        $now = new \DateTimeImmutable();
        $amount = $this->questClearLogic->clear($questId, $context, $now);

        return ['questId' => $questId, 'rewardAmount' => $amount];
    }

    /**
     * クリア前に見込み報酬額をプレビューする。
     */
    public function previewReward(int $baseAmount, UserContext $context): array
    {
        $now = new \DateTimeImmutable();
        $amount = $this->rewardCalculator->applyBonusRate($baseAmount, $context, $now);

        return ['previewAmount' => $amount];
    }
}
