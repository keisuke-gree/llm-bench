<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Model\UserContext;

/**
 * キャンペーン開催期間の判定を行うクラス。
 */
final class CampaignPeriodChecker
{
    /**
     * 指定した日時が、ユーザーコンテキストに紐づくキャンペーンの開催期間内かどうかを判定する。
     *
     * @param UserContext $context ユーザーの実行時コンテキスト
     * @param \DateTimeImmutable $now 判定基準日時
     */
    public function isWithinPeriod(UserContext $context, \DateTimeImmutable $now): bool
    {
        $startAt = $context->campaignStartAt;
        $endAt = $context->campaignEndAt;

        if ($startAt === null || $endAt === null) {
            return false;
        }

        if ($now < $startAt) {
            return false;
        }

        if ($now < $endAt) {
            return true;
        }

        return false;
    }

    /**
     * 開催期間の残り秒数を返す。期間外の場合は0を返す。
     */
    public function remainingSeconds(UserContext $context, \DateTimeImmutable $now): int
    {
        if (!$this->isWithinPeriod($context, $now)) {
            return 0;
        }

        return $context->campaignEndAt->getTimestamp() - $now->getTimestamp();
    }
}
