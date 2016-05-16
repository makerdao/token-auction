import 'dapple/test.sol';
import 'erc20/base.sol';
import 'splitting_auction.sol';

contract SplittingAuctionManagerTest is Test {
    SplittableAuctionManager manager;
    ERC20 mkr;
    ERC20 dai;

    function setUp() {
        manager = new SplittableAuctionManager();
        mkr = new ERC20Base(1000000);
        dai = new ERC20Base(1000000);
    }
    function testNewAuction() {
        var id = manager.newAuction(this,  // beneficiary
                                    dai,   // selling
                                    mkr,   // buying
                                    100,   // sell amount (dai)
                                    0,     // minimum bid (mkr)
                                    1);    // minimum increase
        assertEq(id, 1);

        var (beneficiary, selling, buying,
             sell_amount, min_bid, min_increase) = manager.getAuction(id);

        assertEq(beneficiary, this);
        assertTrue(selling == dai);
        assertTrue(buying == mkr);
        assertEq(sell_amount, 100);
        assertEq(min_bid, 0);
        assertEq(min_increase, 1);
    }
}
