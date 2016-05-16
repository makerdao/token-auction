import 'dapple/test.sol';
import 'splitting_auction.sol';

contract SplittingAuctionManagerTest is Test {
    SplittableAuctionManager manager;
    function setUp() {
        manager = new SplittableAuctionManager();
    }
}
