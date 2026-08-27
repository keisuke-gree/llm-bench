<?php

declare(strict_types=1);

namespace Bench\Logic;

/**
 * イベント開催期間の判定を行うクラス。
 */
final class EventPeriodChecker
{
    /**
     * 指定した日時がイベント開催期間内かどうかを判定する。
     * 開始・終了の両境界を含む閉区間として扱う。
     */
    public function isWithinPeriod(\DateTimeImmutable $startAt, \DateTimeImmutable $endAt, \DateTimeImmutable $now): bool
    {
        if ($now < $startAt) {
            return false;
        }

        if ($now <= $endAt) {
            return true;
        }

        return false;
    }

    public function daysUntilEnd(\DateTimeImmutable $endAt, \DateTimeImmutable $now): int
    {
        if ($now > $endAt) {
            return 0;
        }

        $diff = $endAt->diff($now);

        return $diff->days;
    }
}
