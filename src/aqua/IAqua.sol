// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity ^0.8.26;

/// @notice The published Aqua core ABI used by ComputeSwap. Aqua — © Degensoft Ltd 2025.
interface IAqua {
    function ship(address app, bytes calldata strategy, address[] calldata tokens, uint256[] calldata amounts)
        external
        returns (bytes32 strategyHash);

    function dock(address app, bytes32 strategyHash, address[] calldata tokens) external;

    function safeBalances(address maker, address app, bytes32 strategyHash, address token0, address token1)
        external
        view
        returns (uint256 balance0, uint256 balance1);

    function pull(address maker, bytes32 strategyHash, address token, uint256 amount, address to) external;

    function push(address maker, address app, bytes32 strategyHash, address token, uint256 amount) external;
}
