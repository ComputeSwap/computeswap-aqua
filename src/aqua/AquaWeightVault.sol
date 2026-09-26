// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.26;

import {ERC721} from "solady/tokens/ERC721.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {LogCurveMath} from "../libraries/LogCurveMath.sol";
import {WeightToken} from "../weights/WeightToken.sol";
import {ComputeAquaApp} from "./ComputeAquaApp.sol";
import {IAqua} from "./IAqua.sol";

interface IERC20DecimalsAqua {
    function decimals() external view returns (uint8);
}

interface IERC20BalanceAquaVault {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AquaWeightVault
/// @notice ERC721 LP ownership and ERC6909 leg claims outside Aqua's indivisible strategies.
/// @dev ComputeSwap at ETHGlobal 2026. The vault is the Aqua maker and keeps each strategy fully backed.
///      Partial withdrawal/exercise docks a whole strategy and atomically ships the remainder with a fresh salt.
contract AquaWeightVault is ERC721, ReentrancyGuard {
    error InvalidPosition();
    error NotOwnerOrApproved();
    error LiquidityLocked(uint128 free);
    error InvalidSplit();
    error SeriesStillActive();
    error SeriesExpired();
    error OracleDeviation(int24 tick, int24 emaTick);
    error Slippage();
    error DeadlineExpired();
    error UnbackedPosition();
    error UnsupportedToken();

    event PositionMinted(
        uint256 indexed positionId, address indexed owner, bytes32 indexed strategyHash, uint128 liquidity
    );
    event PositionRolled(uint256 indexed positionId, bytes32 indexed oldHash, bytes32 indexed newHash, uint128 removed);
    event Split(uint256 indexed positionId, uint256 indexed seriesId, uint8 leg, uint128 units, uint64 expiry);
    event Exercised(
        uint256 indexed seriesId, address indexed holder, uint128 units, uint256 legAmount, uint256 otherAmount
    );
    event Merged(uint256 indexed seriesId, uint128 units);
    event Owed(address indexed owner, address indexed token, uint256 amount);

    struct Position {
        address token0;
        address token1;
        uint160 sqrtLowerX96;
        uint160 sqrtUpperX96;
        uint128 liquidity;
        uint24 feeBps;
        uint64 nonce;
        uint256 activeSeries;
        bytes32 strategyHash;
    }

    struct Series {
        uint256 positionId;
        uint64 expiry;
        uint8 leg;
        uint128 remaining;
    }

    struct Removal {
        uint256 principal0;
        uint256 principal1;
        uint256 fees0;
        uint256 fees1;
    }

    struct Accounting {
        uint256 balance0;
        uint256 balance1;
        uint256 principal0;
        uint256 principal1;
        uint256 principal0Left;
        uint256 principal1Left;
    }

    ComputeAquaApp public immutable app;
    IAqua public immutable AQUA;
    WeightToken public immutable weights;
    uint24 public immutable maxOracleDeviation;
    uint256 public nextPositionId = 1;
    uint256 public nextSeriesId = 1;
    mapping(uint256 => Position) internal _positions;
    mapping(uint256 => Series) public series;
    mapping(address => mapping(address => uint256)) public owed;
    mapping(address => bool) private _approvedToAqua;

    constructor(ComputeAquaApp _app, uint24 _maxOracleDeviation) {
        app = _app;
        AQUA = _app.AQUA();
        maxOracleDeviation = _maxOracleDeviation;
        weights = new WeightToken();
    }

    function mint(
        address token0,
        address token1,
        uint160 sqrtLowerX96,
        uint160 sqrtUpperX96,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint24 feeBps,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 deadline
    ) external nonReentrant returns (uint256 positionId, uint256 amount0, uint256 amount1) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (
            token0 == address(0) || token1 == address(0) || token0 == token1 || liquidity == 0
                || sqrtLowerX96 >= sqrtPriceX96 || sqrtPriceX96 >= sqrtUpperX96 || feeBps >= 10_000
        ) {
            revert InvalidPosition();
        }
        amount0 = LogCurveMath.getAmount0Delta(sqrtPriceX96, sqrtUpperX96, liquidity, true);
        amount1 = LogCurveMath.getAmount1Delta(sqrtLowerX96, sqrtPriceX96, liquidity, true);
        if (amount0 > amount0Max || amount1 > amount1Max) revert Slippage();

        positionId = nextPositionId++;
        Position storage p = _positions[positionId];
        p.token0 = token0;
        p.token1 = token1;
        p.sqrtLowerX96 = sqrtLowerX96;
        p.sqrtUpperX96 = sqrtUpperX96;
        p.liquidity = liquidity;
        p.feeBps = feeBps;
        p.nonce = 1;

        _takeExact(token0, amount0);
        _takeExact(token1, amount1);
        _approveAqua(token0);
        _approveAqua(token1);

        ComputeAquaApp.Strategy memory strategy = _strategy(positionId, p);
        bytes32 id = AQUA.ship(address(app), abi.encode(strategy), _tokens(p), _amounts(amount0, amount1));
        if (id != app.hash(strategy)) revert InvalidPosition();
        app.activate(strategy, sqrtPriceX96);
        p.strategyHash = id;
        _mint(msg.sender, positionId);
        emit PositionMinted(positionId, msg.sender, id, liquidity);
    }

    /// @notice Withdraw unlocked liquidity and its pro-rata accrued fees.
    function decreaseLiquidity(
        uint256 positionId,
        uint128 units,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (!_isApprovedOrOwner(msg.sender, positionId)) revert NotOwnerOrApproved();
        if (block.timestamp > deadline) revert DeadlineExpired();
        Position storage p = _positions[positionId];
        uint128 free = p.liquidity - lockedLiquidity(positionId);
        if (units == 0 || units > free) revert LiquidityLocked(free);
        Removal memory r = _roll(positionId, p, units);
        amount0 = r.principal0 + r.fees0;
        amount1 = r.principal1 + r.fees1;
        if (amount0 < amount0Min || amount1 < amount1Min) revert Slippage();
        address owner = ownerOf(positionId);
        _payOwner(p.token0, owner, amount0);
        _payOwner(p.token1, owner, amount1);
    }

    function split(uint256 positionId, uint128 units, uint8 leg, uint64 duration)
        external
        nonReentrant
        returns (uint256 seriesId)
    {
        if (!_isApprovedOrOwner(msg.sender, positionId)) revert NotOwnerOrApproved();
        Position storage p = _positions[positionId];
        if (lockedLiquidity(positionId) != 0) revert SeriesStillActive();
        if (units == 0 || units > p.liquidity || leg > 1 || duration == 0) revert InvalidSplit();
        seriesId = nextSeriesId++;
        uint64 expiry = uint64(block.timestamp) + duration;
        series[seriesId] = Series({positionId: positionId, expiry: expiry, leg: leg, remaining: units});
        p.activeSeries = seriesId;
        uint8 decimals = 18;
        try IERC20DecimalsAqua(p.token1).decimals() returns (uint8 d) {
            decimals = d;
        } catch {}
        weights.createSeries(seriesId, positionId, expiry, leg, decimals);
        weights.mint(ownerOf(positionId), seriesId, units);
        emit Split(positionId, seriesId, leg, units, expiry);
    }

    function exercise(uint256 seriesId, uint128 units, uint256 minLegAmount, uint256 deadline)
        external
        nonReentrant
        returns (uint256 legAmount, uint256 otherAmount)
    {
        Series storage s = series[seriesId];
        if (units == 0 || units > s.remaining || block.timestamp >= s.expiry) revert SeriesExpired();
        if (block.timestamp > deadline) revert DeadlineExpired();
        Position storage p = _positions[s.positionId];
        (int24 tick, int24 emaTick) = app.getOracle(p.strategyHash);
        int256 d = int256(tick) - int256(emaTick);
        if ((d < 0 ? -d : d) > int256(uint256(maxOracleDeviation))) revert OracleDeviation(tick, emaTick);
        weights.burn(msg.sender, seriesId, units);
        s.remaining -= units;
        Removal memory r = _roll(s.positionId, p, units);
        address owner = ownerOf(s.positionId);
        if (s.leg == 0) {
            legAmount = r.principal0;
            otherAmount = r.principal1;
            if (legAmount < minLegAmount) revert Slippage();
            SafeTransferLib.safeTransfer(p.token0, msg.sender, legAmount);
            _payOwner(p.token0, owner, r.fees0);
            _payOwner(p.token1, owner, otherAmount + r.fees1);
        } else {
            legAmount = r.principal1;
            otherAmount = r.principal0;
            if (legAmount < minLegAmount) revert Slippage();
            SafeTransferLib.safeTransfer(p.token1, msg.sender, legAmount);
            _payOwner(p.token1, owner, r.fees1);
            _payOwner(p.token0, owner, otherAmount + r.fees0);
        }
        emit Exercised(seriesId, msg.sender, units, legAmount, otherAmount);
    }

    function merge(uint256 seriesId, uint128 units) external nonReentrant {
        Series storage s = series[seriesId];
        if (!_isApprovedOrOwner(msg.sender, s.positionId)) revert NotOwnerOrApproved();
        if (units == 0 || units > s.remaining || block.timestamp >= s.expiry) revert SeriesExpired();
        weights.burn(msg.sender, seriesId, units);
        s.remaining -= units;
        emit Merged(seriesId, units);
    }

    function claim(address token, address to) external nonReentrant returns (uint256 amount) {
        amount = owed[msg.sender][token];
        owed[msg.sender][token] = 0;
        SafeTransferLib.safeTransfer(token, to, amount);
    }

    function lockedLiquidity(uint256 positionId) public view returns (uint128) {
        uint256 id = _positions[positionId].activeSeries;
        return id != 0 && block.timestamp < series[id].expiry ? series[id].remaining : 0;
    }

    function getPosition(uint256 positionId) external view returns (Position memory position, address owner) {
        position = _positions[positionId];
        owner = _ownerOf(positionId);
    }

    function strategyOf(uint256 positionId) external view returns (ComputeAquaApp.Strategy memory) {
        return _strategy(positionId, _positions[positionId]);
    }

    function previewExercise(uint256 seriesId, uint128 units)
        external
        view
        returns (uint256 legAmount, uint256 otherAmount, bool allowed, int24 tick, int24 emaTick)
    {
        Series storage s = series[seriesId];
        Position storage p = _positions[s.positionId];
        if (units == 0 || units > s.remaining || p.liquidity == 0) return (0, 0, false, 0, 0);
        uint160 price = _price(p.strategyHash);
        (uint256 total0, uint256 total1) = _principal(p, price, p.liquidity);
        (uint256 remain0, uint256 remain1) = _principal(p, price, p.liquidity - units);
        (legAmount, otherAmount) =
            s.leg == 0 ? (total0 - remain0, total1 - remain1) : (total1 - remain1, total0 - remain0);
        (tick, emaTick) = app.getOracle(p.strategyHash);
        int256 d = int256(tick) - int256(emaTick);
        allowed = block.timestamp < s.expiry && (d < 0 ? -d : d) <= int256(uint256(maxOracleDeviation));
    }

    function name() public pure override returns (string memory) {
        return "ComputeSwap Aqua LP";
    }

    function symbol() public pure override returns (string memory) {
        return "CSALP";
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    function _roll(uint256 positionId, Position storage p, uint128 units) private returns (Removal memory r) {
        bytes32 oldId = p.strategyHash;
        uint160 price = _price(oldId);
        uint128 remainingLiquidity = p.liquidity - units;
        uint256 remainBalance0;
        uint256 remainBalance1;
        {
            Accounting memory a;
            (a.balance0, a.balance1) = AQUA.safeBalances(address(this), address(app), oldId, p.token0, p.token1);
            (a.principal0, a.principal1) = _principal(p, price, p.liquidity);
            if (a.balance0 < a.principal0 || a.balance1 < a.principal1) revert UnbackedPosition();
            (a.principal0Left, a.principal1Left) = _principal(p, price, remainingLiquidity);
            r.principal0 = a.principal0 - a.principal0Left;
            r.principal1 = a.principal1 - a.principal1Left;
            r.fees0 = FullMath.mulDiv(a.balance0 - a.principal0, units, p.liquidity);
            r.fees1 = FullMath.mulDiv(a.balance1 - a.principal1, units, p.liquidity);
            remainBalance0 = a.balance0 - r.principal0 - r.fees0;
            remainBalance1 = a.balance1 - r.principal1 - r.fees1;
        }

        AQUA.dock(address(app), oldId, _tokens(p));
        p.liquidity = remainingLiquidity;
        p.nonce++;
        if (remainingLiquidity == 0) {
            p.strategyHash = bytes32(0);
            app.retire(oldId);
            emit PositionRolled(positionId, oldId, bytes32(0), units);
        } else {
            ComputeAquaApp.Strategy memory strategy = _strategy(positionId, p);
            bytes32 newId =
                AQUA.ship(address(app), abi.encode(strategy), _tokens(p), _amounts(remainBalance0, remainBalance1));
            if (newId != app.hash(strategy)) revert InvalidPosition();
            app.activateRollover(oldId, strategy, price);
            p.strategyHash = newId;
            emit PositionRolled(positionId, oldId, newId, units);
        }
    }

    function _strategy(uint256 positionId, Position storage p) private view returns (ComputeAquaApp.Strategy memory) {
        return ComputeAquaApp.Strategy({
            maker: address(this),
            token0: p.token0,
            token1: p.token1,
            sqrtLowerX96: p.sqrtLowerX96,
            sqrtUpperX96: p.sqrtUpperX96,
            liquidity: p.liquidity,
            feeBps: p.feeBps,
            salt: keccak256(abi.encode(positionId, p.nonce))
        });
    }

    function _principal(Position storage p, uint160 price, uint128 liquidity)
        private
        view
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity == 0) return (0, 0);
        amount0 = LogCurveMath.getAmount0Delta(price, p.sqrtUpperX96, liquidity, true);
        amount1 = LogCurveMath.getAmount1Delta(p.sqrtLowerX96, price, liquidity, true);
    }

    function _price(bytes32 id) private view returns (uint160 price) {
        (price,,,) = app.states(id);
    }

    function _tokens(Position storage p) private view returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = p.token0;
        tokens[1] = p.token1;
    }

    function _amounts(uint256 amount0, uint256 amount1) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
    }

    function _approveAqua(address token) private {
        if (_approvedToAqua[token]) return;
        _approvedToAqua[token] = true;
        SafeTransferLib.safeApproveWithRetry(token, address(AQUA), type(uint256).max);
    }

    function _takeExact(address token, uint256 amount) private {
        uint256 balanceBefore = IERC20BalanceAquaVault(token).balanceOf(address(this));
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        if (IERC20BalanceAquaVault(token).balanceOf(address(this)) != balanceBefore + amount) {
            revert UnsupportedToken();
        }
    }

    function _payOwner(address token, address owner, uint256 amount) private {
        if (amount == 0) return;
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, owner, amount));
        if (ok && (data.length == 0 ? token.code.length != 0 : data.length >= 32 && abi.decode(data, (bool)))) return;
        owed[owner][token] += amount;
        emit Owed(owner, token, amount);
    }
}
