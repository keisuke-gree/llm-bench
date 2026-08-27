<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * お知らせメールの情報を保持するモデル。
 */
final class MailModel
{
    public function __construct(
        public readonly int $mailId,
        public readonly string $name,
        public readonly \DateTimeImmutable $registeredAt,
    ) {
    }

    /**
     * 表示用ラベルを組み立てる。
     */
    public function displayLabel(): string
    {
        return sprintf('%s (#%d)', $this->name, $this->mailId);
    }

    /**
     * @return array<string,mixed>
     */
    public function toArray(): array
    {
        return [
            'mailId' => $this->mailId,
            'name' => $this->name,
        ];
    }
}
