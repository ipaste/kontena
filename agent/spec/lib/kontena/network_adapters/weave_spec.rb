describe Kontena::NetworkAdapters::Weave, :celluloid => true do
  let(:actor) { described_class.new(start: false) }
  subject { actor.wrapped_object }

  let(:node_info_worker) { instance_double(Kontena::Workers::NodeInfoWorker) }
  let(:weave_launcher) { instance_double(Kontena::Launchers::Weave) }
  let(:ipam_plugin_launcher) { instance_double(Kontena::Launchers::IpamPlugin) }

  let(:weavewait_container) { double(Docker::Container,

  )}
  let(:node_info) { instance_double(Node,
    grid_subnet: '10.81.0.0/16',
    grid_iprange: '10.81.128.0/17',
  )}
  let(:weave_info) { double() }
  let(:ipam_info) { double() }

  let(:ipam_client) { instance_double(Kontena::NetworkAdapters::IpamClient) }
  let(:bridge_ip) { '172.18.42.1' }

  before do
    stub_const('Kontena::NetworkAdapters::Weave::WEAVE_VERSION', '1.9.3')

    allow(Celluloid::Actor).to receive(:[]).with(:node_info_worker).and_return(node_info_worker)
    allow(Celluloid::Actor).to receive(:[]).with(:weave_launcher).and_return(weave_launcher)
    allow(Celluloid::Actor).to receive(:[]).with(:ipam_plugin_launcher).and_return(ipam_plugin_launcher)

    allow(subject).to receive(:ipam_client).and_return(ipam_client)
    allow(subject).to receive(:interface_ip).with('docker0').and_return(bridge_ip)
  end

  describe '#initialize' do
    it 'calls #start by default' do
      expect_any_instance_of(described_class).to receive(:start)
      described_class.new()
    end
  end

  describe '#start' do
    it 'ensures weavewait and observes' do
      expect(subject).to receive(:ensure_weavewait)

      expect(subject).to receive(:observe).with(node_info_worker, weave_launcher, ipam_plugin_launcher) do |&block|
        expect(subject).to receive(:update).with(node_info)

        block.call(node_info, weave_info, ipam_info)
      end

      actor.start
    end
  end

  describe '#ensure_weavewait' do
    it 'recognizes existing container' do
      expect(subject).to receive(:inspect_container).with('weavewait-1.9.3').and_return(weavewait_container)
      expect(Docker::Container).to_not receive(:create)

      actor.ensure_weavewait
    end

    it 'creates new container' do
      expect(subject).to receive(:inspect_container).with('weavewait-1.9.3').and_return(nil)

      expect(Docker::Container).to receive(:create).with(
        'name' => 'weavewait-1.9.3',
        'Image' => 'weaveworks/weaveexec:1.9.3',
        'Entrypoint' => ['/bin/false'],
        'Labels' => {
          'weavevolumes' => ''
        },
        'Volumes' => {
          '/w' => {},
          '/w-noop' => {},
          '/w-nomcast' => {}
        },
      )

      actor.ensure_weavewait
    end
  end

  describe '#update' do
    let(:ensure_state) { double() }

    it 'ensures and updates observable' do
      expect(subject).to receive(:ensure).with(node_info).and_return(ensure_state)
      expect(subject).to receive(:update_observable).with(ensure_state)

      actor.update(node_info)
      expect(actor).to be_updated
    end

    it 'logs errors and resets observable' do
      expect(subject).to receive(:ensure).with(node_info).and_raise(RuntimeError, 'test')
      expect(subject).to receive(:error).with(RuntimeError)
      expect(subject).to receive(:reset_observable)

      actor.update(node_info)

      expect(actor).to_not be_updated
    end
  end

  describe '#ensure' do
    it 'ensures the default ipam pool' do
      expect(ipam_client).to receive(:reserve_pool).with('kontena', '10.81.0.0/16', '10.81.128.0/17').and_return(
        'PoolID' => 'kontena',
        'Pool' => '10.81.0.0/16',
      )

      expect(subject.ensure(node_info)).to eq(
        ipam_pool: 'kontena',
        ipam_subnet: '10.81.0.0/16',
      )

      expect(subject.ipam_default_pool).to eq 'kontena'
    end
  end

  describe '#modify_container_opts' do
    let(:volumes_from) { [] }
    let(:image_info) { {
        'Config' => {

        },
    } }
    let(:container_opts) { {
        'name' => 'test',
        'Image' => 'test/test',
        'HostConfig' => {
          'NetworkMode' => 'bridge',
          'VolumesFrom' => volumes_from,
        },
        'Labels' => {
          'io.kontena.test' => '1',
        },
    } }
    let(:ipam_response) { {'Address' => '10.81.128.6/16'} }

    before do
      allow(Docker::Image).to receive(:get).with('test/test').and_return(double(info: image_info))
      allow(subject).to receive(:ipam_default_pool).and_return('kontena')
      allow(ipam_client).to receive(:reserve_address).with('kontena').and_return(ipam_response)
    end

    it 'adds weavewait to empty VolumesFrom' do
      subject.modify_container_opts(container_opts)
      expect(container_opts['HostConfig']['VolumesFrom']).to eq ['weavewait-1.9.3:ro']
    end

    it 'adds dns settings' do
      subject.modify_container_opts(container_opts)
      expect(container_opts['HostConfig']['Dns']).to eq [bridge_ip]
    end

    it 'adds ipam labels' do
      subject.modify_container_opts(container_opts)
      expect(container_opts['Labels']).to eq(
        'io.kontena.test' => '1',
        'io.kontena.container.overlay_network' => 'kontena',
        'io.kontena.container.overlay_cidr' => '10.81.128.6/16',
      )
    end

    context 'with VolumesFrom' do
      let(:volumes_from) { ['test-data'] }

      it 'adds weavewait to non-empty VolumesFrom' do
        subject.modify_container_opts(container_opts)
        expect(container_opts['HostConfig']['VolumesFrom']).to eq ['test-data', 'weavewait-1.9.3:ro']
      end
    end
  end
end
