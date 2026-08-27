<?php

declare(strict_types=1);

namespace Bench\Model;

/**
 * リクエスト処理中に参照されるユーザーの実行時コンテキスト。
 * コントローラーからロジック層・DAO層まで一貫して受け渡される。
 */
final class UserContext
{
    public function __construct(
        public readonly int $userId,
        public readonly int $level,
        public ?int $campaignId = null,
        public ?\DateTimeImmutable $campaignStartAt = null,
        public ?\DateTimeImmutable $campaignEndAt = null,
    ) {
    }

    public function hasCampaign(): bool
    {
        return $this->campaignId !== null;
    }

    /**
     * デバッグ表示用の簡易な配列表現を返す。
     */
    public function toArray(): array
    {
        return [
            'userId' => $this->userId,
            'level' => $this->level,
            'campaignId' => $this->campaignId,
        ];
    }
}
