<?php

declare(strict_types=1);

namespace Bench\Tests\Logic;

use Bench\Dao\CampaignDao;
use Bench\Logic\CampaignResolver;
use Bench\Model\UserContext;
use PHPUnit\Framework\TestCase;

/**
 * CampaignResolver::resolve() の動作に関するテスト。
 */
final class CampaignResolverTest extends TestCase
{
    public function testResolveReturnsCampaignRecord(): void
    {
        $campaignDao = $this->createMock(CampaignDao::class);
        $campaignDao->method('findById')->with(101)->willReturn([
            'id' => 101,
            'groupId' => 1,
            'name' => '夏の大感謝祭',
        ]);

        $resolver = new CampaignResolver($campaignDao);

        $context = new UserContext(
            userId: 2001,
            level: 30,
            campaignId: 101,
        );

        $result = $resolver->resolve($context);

        self::assertSame(101, $result['id']);
    }

    public function testResolveReturnsNullWhenNoCampaign(): void
    {
        $campaignDao = $this->createMock(CampaignDao::class);
        $resolver = new CampaignResolver($campaignDao);

        $context = new UserContext(userId: 2002, level: 5, campaignId: null);

        self::assertNull($resolver->resolve($context));
    }
}
