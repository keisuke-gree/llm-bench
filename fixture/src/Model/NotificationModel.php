<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * 通知の情報を保持するモデル。
 */
final class NotificationModel
{
    public function __construct(
        public readonly int $notificationId,
        public readonly string $name,
        public readonly \DateTimeImmutable $registeredAt,
    ) {
    }

    public function isAvailable(\DateTimeImmutable $now): bool
    {
        return $this->registeredAt <= $now;
    }

    /**
     * @return array<string,mixed>
     */
    public function toArray(): array
    {
        return [
            'notificationId' => $this->notificationId,
            'name' => $this->name,
        ];
    }
}
