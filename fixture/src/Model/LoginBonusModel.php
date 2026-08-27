<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * ログインボーナスの情報を保持するモデル。
 */
final class LoginBonusModel
{
    public function __construct(
        public readonly int $loginBonusId,
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
            'loginBonusId' => $this->loginBonusId,
            'name' => $this->name,
        ];
    }
}
