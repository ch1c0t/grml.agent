require_relative 'helper'

describe 'boot command' do
  it 'requires a package profile when offline cache verification is requested' do
    stdout, stderr, status = Open3.capture3('./bin/grml.agent boot --verify-deb-cache')

    expect(status.exitstatus).to eq 1
    expect(stderr).to include 'Usage: grml.agent boot [PROFILE_NAME] [--verify-deb-cache] [--iso PATH]'
  end
end
