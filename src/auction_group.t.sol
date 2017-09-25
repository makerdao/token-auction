pragma solidity ^0.4.15;

import './base.t.sol';
import './auction_group.sol';


contract AuctionGroupTest is AuctionTest {
    function testFailUnequalPayoutsLength() {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;

        uint[] memory payouts = new uint[](1);
        payouts[0] = INFINITY;

        var group = new AuctionGroup(t1, t2, beneficiaries, payouts);
        manager.newAuction(group, t1, t2, 100 * T1, 0 * T2, 1, 1 years);
    }
    function testClaimExcess() {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint[] memory payouts = new uint[](2);
        payouts[0] = 10 * T2;
        payouts[1] = 10 * T2;

        var group = new AuctionGroup(t1, t2, beneficiaries, payouts);
        var (id, base2) = manager.newAuction(group, t1, t2, 100 * T1, 0 * T2, 1, 1 years);

        bidder1.doBid(id, 100 * T2, false);
        group.payout();

        var g_balance_before = t2.balanceOf(group);
        var this_balance_before = t2.balanceOf(this);
        group.claimExcess();
        var this_balance_after = t2.balanceOf(this);

        assertEq(this_balance_after, this_balance_before + g_balance_before);
    }
    function testPayoutGroup() {
        var group = _createGroup();
        var (id, base) = manager.newAuction(group, t1, t2, 100 * T1, 5 * T2, 1, 1 years);

        var g_balance_before = t2.balanceOf(group);
        bidder1.doBid(id, 30 * T2, false);
        var g_balance_after = t2.balanceOf(group);
        assertEq(g_balance_after - g_balance_before, 30 * T2);
    }
    function testPayoutFirstBeneficiary() {
        var group = _createGroup();
        var (id, base) = manager.newAuction(group, t1, t2, 100 * T1, 5 * T2, 1, 1 years);
        bidder1.doBid(id, 30 * T2, false);

        var b1_balance_before = t2.balanceOf(beneficiary1);
        group.payout();
        var b1_balance_after = t2.balanceOf(beneficiary1);
        assertEq(b1_balance_after - b1_balance_before, 10 * T2);
    }
    function testPayoutSecondBeneficiary() {
        var group = _createGroup();
        var (id, base) = manager.newAuction(group, t1, t2, 100 * T1, 5 * T2, 1, 1 years);
        bidder1.doBid(id, 30 * T2, false);

        var b2_balance_before = t2.balanceOf(beneficiary2);
        group.payout();
        var b2_balance_after = t2.balanceOf(beneficiary2);
        assertEq(b2_balance_after - b2_balance_before, 20 * T2);
    }
    function _createGroup() internal returns (AuctionGroup) {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint[] memory payouts = new uint[](2);
        payouts[0] = 10 * T2;
        payouts[1] = INFINITY - 10 * T2;

        return new AuctionGroup(t1, t2, beneficiaries, payouts);
    }
}
