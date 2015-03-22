require 'test_plugin_helper'

module Containers
  class StepsControllerTest < ActionController::TestCase
    setup do
      @container = FactoryGirl.create(:container)
    end

    test 'wizard finishes with a redirect to the managed container' do
      state = DockerContainerWizardState.create!
      Service::Containers.any_instance.expects(:start_container!).with(equals(state))
        .returns(@container)
      put :update, { :wizard_state_id => state.id,
                     :id => :environment,
                     :start_on_create => true,
                     :docker_container_wizard_states_environment => { :tty => false } },
          set_session_user

      assert_redirected_to container_path(:id => @container.id)
    end

    test 'image show doesnot load katello' do
      compute_resource = FactoryGirl.create(:docker_cr)
      state = DockerContainerWizardState.create!
      create_options = { :wizard_state => state,
                         :compute_resource_id => compute_resource.id

                       }
      state.preliminary = DockerContainerWizardStates::Preliminary.create!(create_options)
      DockerContainerWizardState.expects(:find).at_least_once.returns(state)
      get :show, { :wizard_state_id => state.id, :id => :image }, set_session_user
      refute state.image.katello?
      refute response.body.include?("katello") # this is code generated by katello partial
      docker_image = @controller.instance_eval do
        @docker_container_wizard_states_image
      end
      assert_equal state.image, docker_image
    end

    test 'new container respects exposed_ports configuration' do
      state = DockerContainerWizardState.create!
      environment_options = {
        :docker_container_wizard_state_id => state.id
      }
      state.environment = DockerContainerWizardStates::Environment.create!(environment_options)
      state.environment.exposed_ports.create!(:name => '1654', :value => 'tcp')
      state.environment.exposed_ports.create!(:name => '1655', :value => 'udp')
      get :show, { :wizard_state_id => state.id, :id => :environment }, set_session_user
      assert response.body.include?("1654")
      assert response.body.include?("1655")

      # Load ExposedPort variables into container
      state.environment.exposed_ports.each do |e|
        @container.exposed_ports.build :name => e.name,
                                       :value => e.value,
                                       :priority => e.priority
      end
      # Check if parametrized value of container matches Docker API's expectations
      assert @container.parametrize.key? "ExposedPorts"
      assert @container.parametrize["ExposedPorts"].key? "1654/tcp"
      assert @container.parametrize["ExposedPorts"].key? "1655/udp"
    end

    test 'new container respects dns configuration' do
      state = DockerContainerWizardState.create!
      environment_options = {
        :docker_container_wizard_state_id => state.id
      }
      state.environment = DockerContainerWizardStates::Environment.create!(environment_options)
      state.environment.dns.create!(:name => '18.18.18.18')
      state.environment.dns.create!(:name => '19.19.19.19')
      get :show, { :wizard_state_id => state.id, :id => :environment }, set_session_user
      assert response.body.include?("18.18.18.18")
      assert response.body.include?("19.19.19.19")

      # Load Dns variables into container
      state.environment.dns.each do |e|
        @container.dns.build :name => e.name,
                             :priority => e.priority
      end
      # Check if parametrized value of container matches Docker API's expectations
      assert @container.parametrize.key? "HostConfig"
      assert @container.parametrize["HostConfig"].key? "Dns"
      assert @container.parametrize["HostConfig"].value? ["18.18.18.18", "19.19.19.19"]
    end
  end
end
