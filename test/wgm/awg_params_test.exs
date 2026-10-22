defmodule WGM.AWGParamsTest do
  use ExUnit.Case

  alias WGM.Instance.AWGParams
  alias WGM.AWGParamsValidator

  describe "validate/1" do
    test "accepts valid AWG params" do
      params = %AWGParams{
        jc: 5,
        jmin: 50,
        jmax: 100,
        s1: 100,
        s2: 200,
        s3: 300,
        s4: 400,
        h1: "1-10",
        h2: "11-20",
        h3: "21-30",
        h4: "31-40",
        i1: 1,
        i2: 2,
        i3: 3,
        i4: 4,
        i5: 5,
        header_protection_key: "hpk"
      }

      assert AWGParamsValidator.validate(params) == :ok
    end

    test "accepts disabled masking as valid" do
      params = %AWGParams{
        jc: 0,
        jmin: 0,
        jmax: 0,
        s1: 0,
        s2: 0,
        s3: 0,
        s4: 0,
        h1: "1",
        h2: "2",
        h3: "3",
        h4: "4",
        i1: 0,
        i2: 0,
        i3: 0,
        i4: 0,
        i5: 0
      }

      assert AWGParamsValidator.validate(params) == :ok
    end

    test "accepts off and 0-0 as disabled masking" do
      params = %AWGParams{
        jc: 0,
        jmin: 0,
        jmax: 0,
        s1: 0,
        s2: 0,
        s3: 0,
        s4: 0,
        h1: "off",
        h2: "off",
        h3: "off",
        h4: "off",
        i1: 0,
        i2: 0,
        i3: 0,
        i4: 0,
        i5: 0
      }

      assert AWGParamsValidator.validate(params) == :ok

      params2 = %AWGParams{
        jc: 0,
        jmin: 0,
        jmax: 0,
        s1: 0,
        s2: 0,
        s3: 0,
        s4: 0,
        h1: "0-0",
        h2: "0-0",
        h3: "0-0",
        h4: "0-0",
        i1: 0,
        i2: 0,
        i3: 0,
        i4: 0,
        i5: 0
      }

      assert AWGParamsValidator.validate(params2) == :ok
    end

    test "rejects jc out of range" do
      params = awg_params(jc: -1)

      assert {:error, "Jc must be between 1 and 128, or 0 for disabled masking"} =
               AWGParamsValidator.validate(params)

      params = awg_params(jc: 129)

      assert {:error, "Jc must be between 1 and 128, or 0 for disabled masking"} =
               AWGParamsValidator.validate(params)
    end

    test "rejects jmin not less than jmax" do
      params = awg_params(jmin: 100, jmax: 100)
      assert {:error, "Jmin must be less than Jmax"} = AWGParamsValidator.validate(params)
    end

    test "rejects jmax >= 1280" do
      params = awg_params(jmax: 1280)
      assert {:error, "Jmax must be less than 1280"} = AWGParamsValidator.validate(params)
    end

    test "rejects s1 > 1132" do
      params = awg_params(s1: 1133)
      assert {:error, "S1 must be at most 1132"} = AWGParamsValidator.validate(params)
    end

    test "rejects s2 > 1188" do
      params = awg_params(s2: 1189)
      assert {:error, "S2 must be at most 1188"} = AWGParamsValidator.validate(params)
    end

    test "rejects s1 + 56 == s2" do
      params = awg_params(s1: 100, s2: 156)
      assert {:error, "S1 + 56 must not equal S2"} = AWGParamsValidator.validate(params)
    end

    test "rejects overlapping h ranges" do
      params = awg_params(h1: "1-10", h2: "5-15")
      assert {:error, "H ranges must not overlap"} = AWGParamsValidator.validate(params)
    end

    test "rejects invalid h range format" do
      params = awg_params(h1: "abc")
      assert {:error, "Invalid H range format: abc"} = AWGParamsValidator.validate(params)
    end

    test "rejects header protection when s3 is below 12" do
      params = awg_params(header_protection_key: "hpk", s3: 11)

      assert {:error, "S3 must be at least 12 when HeaderProtection is enabled"} =
               AWGParamsValidator.validate(params)
    end

    test "rejects header protection when s4 is below 12" do
      params = awg_params(header_protection_key: "hpk", s4: 5)

      assert {:error, "S4 must be at least 12 when HeaderProtection is enabled"} =
               AWGParamsValidator.validate(params)
    end

    test "accepts header protection when s1-s4 are at least 12" do
      params = awg_params(header_protection_key: "hpk", s1: 12, s2: 12, s3: 12, s4: 12)
      assert AWGParamsValidator.validate(params) == :ok
    end
  end

  defp awg_params(overrides) do
    defaults = %AWGParams{
      jc: 5,
      jmin: 50,
      jmax: 100,
      s1: 100,
      s2: 200,
      s3: 300,
      s4: 400,
      h1: "1-10",
      h2: "11-20",
      h3: "21-30",
      h4: "31-40",
      i1: 1,
      i2: 2,
      i3: 3,
      i4: 4,
      i5: 5
    }

    struct(defaults, overrides)
  end
end
