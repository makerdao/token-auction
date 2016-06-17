import 'tests/base.sol';

contract DBTester is Tester {
    TestableManager _manager;
    function bindManager(address manager) {
        _manager = TestableManager(manager);
    }
    function doSetRefundAddress(uint id, address refund) {
        _manager.setRefundAddress(id, refund);
    }
}

contract AuctionDBTest is AuctionTest {
    DBTester tester;

    function newAuction() returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 1 * T2    // min_increase
                                 , 1 years   // duration
                                 );
    }
    function testDefaultRefund() {
        var (id, base) = newAuction();

        assertEq(manager.getRefundAddress(id), seller);
    }
    function testSetRefund() {
        var (id, base) = newAuction();

        manager.setRefundAddress(id, beneficiary2);
        assertEq(manager.getRefundAddress(id), beneficiary2);
    }
    function testFailSetRefundNotCreator() {
        var (id, base) = newAuction();

        tester = new DBTester();
        tester.bindManager(manager);

        tester.doSetRefundAddress(id, beneficiary2);
    }
}
