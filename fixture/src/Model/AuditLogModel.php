<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * 各種操作の監査ログを表すモデル。
 */
final class AuditLogModel
{
    public const EVENT_APPLY_BONUS_RATE = 'applyBonusRate';
    public const EVENT_GRANT_ITEM = 'grantItem';
    public const EVENT_LOGIN = 'login';

    public function __construct(
        public readonly string $eventName,
        public readonly int $userId,
        public readonly \DateTimeImmutable $occurredAt,
    ) {
    }

    public function toLogLine(): string
    {
        return sprintf(
            '[%s] event=%s user=%d',
            $this->occurredAt->format('Y-m-d H:i:s'),
            $this->eventName,
            $this->userId,
        );
    }
}
