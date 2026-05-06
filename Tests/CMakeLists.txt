add_executable(
  bte_core_tests
  Unit/Core/UnitTest_Bar.cpp)

target_link_libraries(
  bte_core_tests
  PRIVATE
    bte::core
    GTest::gtest_main)

include(GoogleTest)
gtest_discover_tests(bte_core_tests)
