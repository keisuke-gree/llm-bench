<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Model\UserContext;

/**
 * クエスト・イベント報酬の計算を行うクラス。
 * 基礎報酬額の算出と、開催中キャンペーンのボーナスレート適用を担当する。
 */
final class RewardCalculator
{
    private CampaignPeriodChecker $periodChecker;

    public function __construct(?CampaignPeriodChecker $periodChecker = null)
    {
        $this->periodChecker = $periodChecker ?? new CampaignPeriodChecker();
    }

    /**
     * 基礎報酬額に、開催中キャンペーンのボーナスレートを適用する。
     *
     * @param int $baseAmount 基礎報酬額
     * @param UserContext $context ユーザーの実行時コンテキスト
     * @param \DateTimeImmutable $now 判定基準日時
     */
    public function applyBonusRate(int $baseAmount, UserContext $context, \DateTimeImmutable $now): int
    {
        if (!$this->periodChecker->isWithinPeriod($context, $now)) {
            return $baseAmount;
        }

        $bonusRate = $this->resolveBonusRate($context->campaignId);

        return (int) floor($baseAmount * $bonusRate);
    }

    /**
     * キャンペーンごとの倍率テーブルを参照し、該当がなければ1.0倍とする。
     */
    private function resolveBonusRate(?int $campaignId): float
    {
        $rateTable = [
            1 => 1.5,
            2 => 1.3,
            3 => 2.0,
        ];

        if ($campaignId === null) {
            return 1.0;
        }

        return $rateTable[$campaignId] ?? 1.0;
    }

    /**
     * クエストランクとクリア回数から基礎報酬額を算出する。
     */
    public function calculateBaseAmount(int $questRank, int $clearCount): int
    {
        return $questRank * 100 + $clearCount * 10;
    }
}
